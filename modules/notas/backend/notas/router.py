"""Router FastAPI del módulo notas (prefijo /api/notas)."""
import mimetypes
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func, or_, text
from sqlmodel import Session, SQLModel, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .models import Nota, NotaActivo, NotaArchivo, NotaDiagrama, NotaRevision
from .schemas import DiagramaIn, NotaIn, NotaListItem, NotaRead

router = APIRouter(prefix="/notas", tags=["notas"])

MAX_FILE_BYTES = int(os.getenv("NOTAS_MAX_MB", "50") or 50) * 1024 * 1024
MAX_FILES_PER_NOTA = 50
MAX_REVISIONS = 300


def _migrate() -> None:
    if engine.dialect.name != "postgresql":
        return  # SQLite: create_all ya crea el esquema completo
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE nota_diagramas ADD COLUMN IF NOT EXISTS preview TEXT;"))


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate()


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _snippet(body: str) -> str:
    t = " ".join((body or "").split())
    return t[:160] + ("…" if len(t) > 160 else "")


def _merge(n: Nota, links: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for t in ([n.asset_tag] if n.asset_tag else []) + list(links):
        if t.casefold() not in seen:
            seen.add(t.casefold())
            out.append(t)
    return out


def _links_map(session: Session, ids: list[int]) -> dict[int, list[str]]:
    if not ids:
        return {}
    out: dict[int, list[str]] = {}
    for l in session.exec(select(NotaActivo).where(NotaActivo.nota_id.in_(ids)).order_by(NotaActivo.id)).all():
        out.setdefault(l.nota_id, []).append(l.asset_tag)
    return out


def _set_links(session: Session, nota_id: int, tags: list[str]) -> None:
    cur = {l.asset_tag: l for l in session.exec(select(NotaActivo).where(NotaActivo.nota_id == nota_id)).all()}
    for t, l in cur.items():
        if t not in tags:
            session.delete(l)
    for t in tags:
        if t not in cur:
            session.add(NotaActivo(nota_id=nota_id, asset_tag=t))


def _read(n: Nota, links: list[str]) -> NotaRead:
    tags = _merge(n, links)
    return NotaRead(
        id=n.id, title=n.title, body=n.body or "", tags=list(n.tags or []),
        asset_tag=tags[0] if tags else None, asset_tags=tags,
        created_by=n.created_by, updated_by=n.updated_by, created_at=n.created_at, updated_at=n.updated_at,
    )


def _get_or_404(session: Session, nota_id: int) -> Nota:
    n = session.get(Nota, nota_id)
    if not n:
        raise HTTPException(404, detail="Nota no encontrada")
    return n


def _touch(n: Nota, user: str) -> None:
    n.updated_by = user
    n.updated_at = _now()


# ------------------------------------------------------------------ historial
def _snap(title: str, body: str, tags, assets) -> dict:
    return {"title": title, "body": body or "", "tags": list(tags or []), "asset_tags": list(assets or [])}


def _cambios(a: dict, b: dict) -> str:
    names = {"title": "título", "body": "contenido", "tags": "etiquetas", "asset_tags": "activos"}
    return "Cambió: " + ", ".join(v for k, v in names.items() if a.get(k) != b.get(k))


def _log(session: Session, nota_id: int, user: str, action: str, detail: str | None = None, snap: dict | None = None) -> None:
    last = session.exec(select(func.max(NotaRevision.version)).where(NotaRevision.nota_id == nota_id)).one() or 0
    r = NotaRevision(nota_id=nota_id, version=last + 1, action=action, detail=(detail or None) and detail[:300], changed_by=user)
    if snap:
        r.has_snapshot, r.title, r.body, r.tags, r.asset_tags = True, snap["title"], snap["body"], snap["tags"], snap["asset_tags"]
    session.add(r)
    session.flush()
    extra = session.exec(select(NotaRevision.id).where(NotaRevision.nota_id == nota_id).order_by(NotaRevision.id.desc()).offset(MAX_REVISIONS)).all()
    for rid in extra:
        old = session.get(NotaRevision, rid)
        if old:
            session.delete(old)


def _rev_meta(r: NotaRevision) -> dict:
    return {"id": r.id, "version": r.version, "action": r.action, "detail": r.detail, "has_snapshot": r.has_snapshot,
            "changed_by": r.changed_by, "changed_at": r.changed_at.isoformat()}


# IMPORTANTE: /health y /tags van antes que /{nota_id}
@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "notas", "status": "ok"}


@router.get("/tags")
def etiquetas(session: Session = Depends(get_session)):
    conteo: dict[str, int] = {}
    canon: dict[str, str] = {}
    for tags in session.exec(select(Nota.tags)).all():
        for t in tags or []:
            k = t.casefold()
            canon.setdefault(k, t)
            conteo[k] = conteo.get(k, 0) + 1
    return [{"tag": canon[k], "count": n} for k, n in sorted(conteo.items(), key=lambda kv: (-kv[1], kv[0]))]


@router.get("/", response_model=list[NotaListItem])
def listar(
    q: str | None = None,
    tag: str | None = None,
    asset_tag: str | None = None,
    limit: int = Query(500, ge=1, le=2000),
    session: Session = Depends(get_session),
):
    stmt = select(Nota)
    if asset_tag:
        stmt = stmt.where(or_(
            Nota.asset_tag == asset_tag,
            Nota.id.in_(select(NotaActivo.nota_id).where(NotaActivo.asset_tag == asset_tag)),
        ))
    for term in (q or "").split():
        p = f"%{term}%"
        stmt = stmt.where(or_(
            Nota.title.ilike(p), Nota.body.ilike(p), Nota.asset_tag.ilike(p),
            Nota.id.in_(select(NotaActivo.nota_id).where(NotaActivo.asset_tag.ilike(p))),
        ))
    rows = session.exec(stmt.order_by(Nota.updated_at.desc()).limit(limit)).all()
    if tag:
        rows = [n for n in rows if tag.lower() in [t.lower() for t in (n.tags or [])]]
    ids = [n.id for n in rows]
    links = _links_map(session, ids)
    diag, files = {}, {}
    if ids:
        diag = dict(session.exec(select(NotaDiagrama.nota_id, func.count()).where(NotaDiagrama.nota_id.in_(ids)).group_by(NotaDiagrama.nota_id)).all())
        files = dict(session.exec(select(NotaArchivo.nota_id, func.count()).where(NotaArchivo.nota_id.in_(ids)).group_by(NotaArchivo.nota_id)).all())
    out = []
    for n in rows:
        tags = _merge(n, links.get(n.id, []))
        out.append(NotaListItem(
            id=n.id, title=n.title, snippet=_snippet(n.body), tags=list(n.tags or []),
            asset_tag=tags[0] if tags else None, asset_tags=tags, diagram_count=diag.get(n.id, 0), file_count=files.get(n.id, 0),
            created_by=n.created_by, created_at=n.created_at, updated_by=n.updated_by, updated_at=n.updated_at,
        ))
    return out


@router.post("/", response_model=NotaRead, status_code=201)
def crear(payload: NotaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    tags = payload.asset_tags
    data = payload.model_dump(exclude={"asset_tags"})
    data["asset_tag"] = tags[0] if tags else None
    n = Nota(**data, created_by=user, updated_by=user)
    session.add(n)
    session.flush()
    _set_links(session, n.id, tags)
    _log(session, n.id, user, "Creada", snap=_snap(n.title, n.body, n.tags, tags))
    session.commit()
    session.refresh(n)
    return _read(n, tags)


@router.get("/{nota_id}", response_model=NotaRead)
def obtener(nota_id: int, session: Session = Depends(get_session)):
    n = _get_or_404(session, nota_id)
    return _read(n, _links_map(session, [n.id]).get(n.id, []))


@router.put("/{nota_id}", response_model=NotaRead)
def actualizar(nota_id: int, payload: NotaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    tags = payload.asset_tags
    before = _snap(n.title, n.body, n.tags, _merge(n, _links_map(session, [n.id]).get(n.id, [])))
    for k, v in payload.model_dump(exclude={"asset_tags"}).items():
        setattr(n, k, v)
    n.asset_tag = tags[0] if tags else None
    after = _snap(n.title, n.body, n.tags, tags)
    if before != after:
        _touch(n, user)
        _set_links(session, n.id, tags)
        _log(session, n.id, user, "Editada", _cambios(before, after), snap=after)
    session.add(n)
    session.commit()
    session.refresh(n)
    return _read(n, tags)


@router.delete("/{nota_id}", status_code=204)
def eliminar(nota_id: int, session: Session = Depends(get_session)):
    n = _get_or_404(session, nota_id)
    for model in (NotaActivo, NotaDiagrama, NotaRevision):
        for row in session.exec(select(model).where(model.nota_id == nota_id)).all():
            session.delete(row)
    for a in session.exec(select(NotaArchivo).where(NotaArchivo.nota_id == nota_id)).all():
        (_files_dir() / a.stored_name).unlink(missing_ok=True)
        session.delete(a)
    session.delete(n)
    session.commit()


# ------------------------------------------------------------------ historial (consulta y restauración)
@router.get("/{nota_id}/historial")
def historial(nota_id: int, session: Session = Depends(get_session)):
    _get_or_404(session, nota_id)
    rows = session.exec(select(NotaRevision).where(NotaRevision.nota_id == nota_id).order_by(NotaRevision.id.desc())).all()
    return [_rev_meta(r) for r in rows]


def _rev_or_404(session: Session, nota_id: int, rid: int) -> NotaRevision:
    r = session.get(NotaRevision, rid)
    if not r or r.nota_id != nota_id:
        raise HTTPException(404, detail="Versión no encontrada")
    return r


@router.get("/{nota_id}/historial/{rid}")
def ver_version(nota_id: int, rid: int, session: Session = Depends(get_session)):
    r = _rev_or_404(session, nota_id, rid)
    return {**_rev_meta(r), "title": r.title, "body": r.body, "tags": r.tags or [], "asset_tags": r.asset_tags or []}


@router.post("/{nota_id}/historial/{rid}/restore", response_model=NotaRead)
def restaurar(nota_id: int, rid: int, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    r = _rev_or_404(session, nota_id, rid)
    if not r.has_snapshot:
        raise HTTPException(400, detail="Ese registro no guarda contenido para restaurar")
    n.title, n.body, n.tags = r.title or n.title, r.body or "", list(r.tags or [])
    assets = list(r.asset_tags or [])
    n.asset_tag = assets[0] if assets else None
    _set_links(session, n.id, assets)
    _touch(n, user)
    _log(session, n.id, user, "Restaurada", f"Volvió a la versión {r.version}", snap=_snap(n.title, n.body, n.tags, assets))
    session.add(n)
    session.commit()
    session.refresh(n)
    return _read(n, assets)


# ------------------------------------------------------------------ diagramas (draw.io)
def _dg_meta(d: NotaDiagrama) -> dict:
    return {"id": d.id, "title": d.title, "updated_by": d.updated_by, "updated_at": d.updated_at.isoformat(), "preview": d.preview}


def _dg_or_404(session: Session, nota_id: int, did: int) -> NotaDiagrama:
    d = session.get(NotaDiagrama, did)
    if not d or d.nota_id != nota_id:
        raise HTTPException(404, detail="Diagrama no encontrado")
    return d


@router.get("/{nota_id}/diagramas")
def listar_diagramas(nota_id: int, session: Session = Depends(get_session)):
    _get_or_404(session, nota_id)
    rows = session.exec(select(NotaDiagrama).where(NotaDiagrama.nota_id == nota_id).order_by(NotaDiagrama.id)).all()
    return [_dg_meta(d) for d in rows]


@router.post("/{nota_id}/diagramas", status_code=201)
def crear_diagrama(nota_id: int, payload: DiagramaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    d = NotaDiagrama(nota_id=nota_id, title=payload.title, xml=payload.xml, preview=payload.preview, created_by=user, updated_by=user)
    session.add(d)
    _touch(n, user)
    _log(session, nota_id, user, "Creó un diagrama", payload.title)
    session.add(n)
    session.commit()
    session.refresh(d)
    return {**_dg_meta(d), "xml": d.xml}


@router.get("/{nota_id}/diagramas/{did}")
def obtener_diagrama(nota_id: int, did: int, session: Session = Depends(get_session)):
    d = _dg_or_404(session, nota_id, did)
    return {**_dg_meta(d), "xml": d.xml or ""}


@router.put("/{nota_id}/diagramas/{did}")
def actualizar_diagrama(nota_id: int, did: int, payload: DiagramaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    d = _dg_or_404(session, nota_id, did)
    d.title, d.xml, d.updated_by, d.updated_at = payload.title, payload.xml, user, _now()
    if payload.preview:  # sin preview nuevo se conserva el anterior
        d.preview = payload.preview
    _touch(n, user)  # el autoguardado no escribe en el historial: solo mueve "última edición"
    session.add(d)
    session.add(n)
    session.commit()
    session.refresh(d)
    return {**_dg_meta(d), "xml": d.xml}


@router.delete("/{nota_id}/diagramas/{did}", status_code=204)
def eliminar_diagrama(nota_id: int, did: int, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    d = _dg_or_404(session, nota_id, did)
    _touch(n, user)
    _log(session, nota_id, user, "Eliminó un diagrama", d.title)
    session.delete(d)
    session.add(n)
    session.commit()


# ------------------------------------------------------------------ archivos adjuntos (cualquier tipo)
def _files_dir() -> Path:
    d = Path(os.getenv("UPLOADS_DIR", "/app/uploads")) / "_private" / "notas"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _ar_out(a: NotaArchivo) -> dict:
    return {"id": a.id, "original_name": a.original_name, "content_type": a.content_type, "size": a.size,
            "created_by": a.created_by, "created_at": a.created_at.isoformat()}


def _ar_or_404(session: Session, nota_id: int, aid: int) -> NotaArchivo:
    a = session.get(NotaArchivo, aid)
    if not a or a.nota_id != nota_id:
        raise HTTPException(404, detail="Archivo no encontrado")
    return a


@router.get("/{nota_id}/archivos")
def listar_archivos(nota_id: int, session: Session = Depends(get_session)):
    _get_or_404(session, nota_id)
    rows = session.exec(select(NotaArchivo).where(NotaArchivo.nota_id == nota_id).order_by(NotaArchivo.id)).all()
    return [_ar_out(a) for a in rows]


@router.post("/{nota_id}/archivos", status_code=201)
async def subir_archivos(nota_id: int, files: list[UploadFile] = File(...), session: Session = Depends(get_session),
                         user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    ya = session.exec(select(func.count()).select_from(NotaArchivo).where(NotaArchivo.nota_id == nota_id)).one()
    if ya + len(files) > MAX_FILES_PER_NOTA:
        raise HTTPException(400, detail=f"Máximo {MAX_FILES_PER_NOTA} archivos por nota")
    written: list[tuple[Path, str, int, str | None]] = []
    try:
        for f in files:
            name = (f.filename or "archivo").replace("\\", "/").split("/")[-1].strip()[:255] or "archivo"
            path = _files_dir() / uuid.uuid4().hex
            size = 0
            written.append((path, name, 0, None))  # registrado antes para limpiar si falla a mitad
            with path.open("wb") as out:
                while chunk := await f.read(1024 * 1024):
                    size += len(chunk)
                    if size > MAX_FILE_BYTES:
                        raise HTTPException(413, detail=f"'{name}' supera {MAX_FILE_BYTES // (1024 * 1024)} MB")
                    out.write(chunk)
            ctype = f.content_type if f.content_type and f.content_type != "application/octet-stream" else mimetypes.guess_type(name)[0]
            written[-1] = (path, name, size, ctype)
    except BaseException:
        for p, *_ in written:
            p.unlink(missing_ok=True)
        raise
    nuevos = []
    for path, name, size, ctype in written:
        a = NotaArchivo(nota_id=nota_id, stored_name=path.name, original_name=name, content_type=ctype, size=size, created_by=user)
        session.add(a)
        nuevos.append(a)
        _log(session, nota_id, user, "Adjuntó un archivo", name)
    _touch(n, user)
    session.add(n)
    session.commit()
    for a in nuevos:
        session.refresh(a)
    return [_ar_out(a) for a in nuevos]


@router.get("/{nota_id}/archivos/{aid}/download")
def descargar_archivo(nota_id: int, aid: int, session: Session = Depends(get_session)):
    a = _ar_or_404(session, nota_id, aid)
    p = _files_dir() / a.stored_name
    if not p.exists():
        raise HTTPException(404, detail="El archivo ya no está en el servidor")
    return FileResponse(p, filename=a.original_name, media_type=a.content_type or "application/octet-stream")


@router.delete("/{nota_id}/archivos/{aid}", status_code=204)
def eliminar_archivo(nota_id: int, aid: int, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    a = _ar_or_404(session, nota_id, aid)
    (_files_dir() / a.stored_name).unlink(missing_ok=True)
    _touch(n, user)
    _log(session, nota_id, user, "Eliminó un archivo", a.original_name)
    session.delete(a)
    session.add(n)
    session.commit()
