"""Router FastAPI del módulo notas (prefijo /api/notas)."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_
from sqlmodel import Session, SQLModel, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .models import Nota, NotaActivo, NotaDiagrama
from .schemas import DiagramaIn, NotaIn, NotaListItem, NotaRead

router = APIRouter(prefix="/notas", tags=["notas"])


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _snippet(body: str) -> str:
    t = " ".join((body or "").split())
    return t[:160] + ("…" if len(t) > 160 else "")


def _merge(n: Nota, links: list[str]) -> list[str]:
    """Tags vinculados: el campo legado (si existe) primero y luego los de nota_activos, sin repetir."""
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


# IMPORTANTE: /health y /tags van antes que /{nota_id}
@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "notas", "status": "ok"}


@router.get("/tags")
def etiquetas(session: Session = Depends(get_session)):
    conteo: dict[str, int] = {}
    for tags in session.exec(select(Nota.tags)).all():
        for t in tags or []:
            conteo[t] = conteo.get(t, 0) + 1
    return [{"tag": t, "count": n} for t, n in sorted(conteo.items(), key=lambda kv: (-kv[1], kv[0].lower()))]


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
    diag = {}
    if ids:
        diag = {nid: c for nid, c in session.exec(
            select(NotaDiagrama.nota_id, func.count()).where(NotaDiagrama.nota_id.in_(ids)).group_by(NotaDiagrama.nota_id)
        ).all()}
    out = []
    for n in rows:
        tags = _merge(n, links.get(n.id, []))
        out.append(NotaListItem(
            id=n.id, title=n.title, snippet=_snippet(n.body), tags=list(n.tags or []),
            asset_tag=tags[0] if tags else None, asset_tags=tags, diagram_count=diag.get(n.id, 0),
            updated_by=n.updated_by, updated_at=n.updated_at,
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
    for k, v in payload.model_dump(exclude={"asset_tags"}).items():
        setattr(n, k, v)
    n.asset_tag = tags[0] if tags else None
    n.updated_by = user
    n.updated_at = _now()
    _set_links(session, n.id, tags)
    session.add(n)
    session.commit()
    session.refresh(n)
    return _read(n, tags)


@router.delete("/{nota_id}", status_code=204)
def eliminar(nota_id: int, session: Session = Depends(get_session)):
    n = _get_or_404(session, nota_id)
    for l in session.exec(select(NotaActivo).where(NotaActivo.nota_id == nota_id)).all():
        session.delete(l)
    for d in session.exec(select(NotaDiagrama).where(NotaDiagrama.nota_id == nota_id)).all():
        session.delete(d)
    session.delete(n)
    session.commit()


# ------------------------------------------------------------------ diagramas (draw.io)
def _dg_meta(d: NotaDiagrama) -> dict:
    return {"id": d.id, "title": d.title, "updated_by": d.updated_by, "updated_at": d.updated_at.isoformat()}


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
    _get_or_404(session, nota_id)
    d = NotaDiagrama(nota_id=nota_id, title=payload.title, xml=payload.xml, created_by=user, updated_by=user)
    session.add(d)
    session.commit()
    session.refresh(d)
    return {**_dg_meta(d), "xml": d.xml}


@router.get("/{nota_id}/diagramas/{did}")
def obtener_diagrama(nota_id: int, did: int, session: Session = Depends(get_session)):
    d = _dg_or_404(session, nota_id, did)
    return {**_dg_meta(d), "xml": d.xml or ""}


@router.put("/{nota_id}/diagramas/{did}")
def actualizar_diagrama(nota_id: int, did: int, payload: DiagramaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    d = _dg_or_404(session, nota_id, did)
    d.title, d.xml, d.updated_by, d.updated_at = payload.title, payload.xml, user, _now()
    session.add(d)
    session.commit()
    session.refresh(d)
    return {**_dg_meta(d), "xml": d.xml}


@router.delete("/{nota_id}/diagramas/{did}", status_code=204)
def eliminar_diagrama(nota_id: int, did: int, session: Session = Depends(get_session)):
    d = _dg_or_404(session, nota_id, did)
    session.delete(d)
    session.commit()
