"""Router FastAPI del módulo tickets (prefijo /api/tickets). Permisos: tickets.ver / editar / eliminar (guard en main.py)."""
import mimetypes
import os
import re
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func, or_
from sqlmodel import Session, SQLModel, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .hooks import hooks
from .models import Ticket, TicketArchivo, TicketComment
from .schemas import CommentIn, TicketIn

router = APIRouter(prefix="/tickets", tags=["tickets"])

CLOSED = ("Resuelto", "Cerrado")
MAX_FILE_BYTES = int(os.getenv("TICKETS_MAX_MB", "50") or 50) * 1024 * 1024
MAX_FILES_PER_TICKET = 30
_NUM = re.compile(r"^t?-?0*(\d+)$", re.I)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _get_or_404(session: Session, tid: int) -> Ticket:
    t = session.get(Ticket, tid)
    if not t:
        raise HTTPException(404, detail="Ticket no encontrado")
    return t


def _event(session: Session, tid: int, user: str, text: str) -> None:
    session.add(TicketComment(ticket_id=tid, kind="evento", body=text, author=user))


def _vencido(t: Ticket) -> bool:
    return bool(t.due_date and t.due_date < date.today() and t.status not in CLOSED)


def _out(t: Ticket, comments: int = 0, files: int = 0) -> dict:
    return {
        "id": t.id, "title": t.title, "description": t.description, "status": t.status, "priority": t.priority,
        "category": t.category, "requester_id": t.requester_id, "requester_name": t.requester_name,
        "asset_tag": t.asset_tag, "assignee": t.assignee, "due_date": t.due_date.isoformat() if t.due_date else None,
        "created_by": t.created_by, "created_at": t.created_at.isoformat(), "updated_at": t.updated_at.isoformat(),
        "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
        "vencido": _vencido(t), "comment_count": comments, "file_count": files,
    }


def _apply_status(t: Ticket, new: str) -> None:
    if new in CLOSED and t.resolved_at is None:
        t.resolved_at = _now()
    elif new not in CLOSED:
        t.resolved_at = None


# IMPORTANTE: rutas fijas antes que /{tid}
@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "tickets", "status": "ok"}


@router.get("/usuarios")
def usuarios(session: Session = Depends(get_session)):
    """Usuarios activos del sistema que pueden ser responsables."""
    return hooks.users(session)


@router.get("/resumen")
def resumen(session: Session = Depends(get_session), user: str = Depends(current_user)):
    abiertos = Ticket.status.not_in(CLOSED)

    def n(*conds) -> int:
        return session.exec(select(func.count()).select_from(Ticket).where(*conds)).one()

    por_estado = dict(session.exec(select(Ticket.status, func.count()).group_by(Ticket.status)).all())
    por_prioridad = dict(session.exec(select(Ticket.priority, func.count()).where(abiertos).group_by(Ticket.priority)).all())
    return {
        "abiertos": n(abiertos),
        "sin_asignar": n(abiertos, Ticket.assignee.is_(None)),
        "vencidos": n(abiertos, Ticket.due_date.is_not(None), Ticket.due_date < date.today()),
        "criticos": n(abiertos, Ticket.priority == "Crítica"),
        "mios": n(abiertos, Ticket.assignee == user),
        "por_estado": por_estado,
        "por_prioridad": por_prioridad,
    }


@router.get("/")
def listar(
    q: str | None = None,
    status: str | None = None,
    priority: str | None = None,
    assignee: str | None = None,   # "_none" = sin asignar
    asset_tag: str | None = None,
    requester_id: int | None = None,
    abiertos: bool = False,
    mios: bool = False,
    limit: int = Query(500, ge=1, le=2000),
    session: Session = Depends(get_session),
    user: str = Depends(current_user),
):
    stmt = select(Ticket)
    if abiertos:
        stmt = stmt.where(Ticket.status.not_in(CLOSED))
    if status:
        stmt = stmt.where(Ticket.status == status)
    if priority:
        stmt = stmt.where(Ticket.priority == priority)
    if mios:
        stmt = stmt.where(Ticket.assignee == user)
    elif assignee == "_none":
        stmt = stmt.where(Ticket.assignee.is_(None))
    elif assignee:
        stmt = stmt.where(Ticket.assignee == assignee)
    if asset_tag:
        stmt = stmt.where(Ticket.asset_tag == asset_tag)
    if requester_id is not None:
        stmt = stmt.where(Ticket.requester_id == requester_id)
    for term in (q or "").split():
        p = f"%{term}%"
        conds = [Ticket.title.ilike(p), Ticket.description.ilike(p), Ticket.asset_tag.ilike(p),
                 Ticket.requester_name.ilike(p), Ticket.assignee.ilike(p), Ticket.category.ilike(p)]
        m = _NUM.match(term)
        if m:
            conds.append(Ticket.id == int(m.group(1)))
        stmt = stmt.where(or_(*conds))
    rows = session.exec(stmt.order_by(Ticket.updated_at.desc()).limit(limit)).all()
    ids = [t.id for t in rows]
    cc, fc = {}, {}
    if ids:
        cc = dict(session.exec(select(TicketComment.ticket_id, func.count()).where(TicketComment.ticket_id.in_(ids), TicketComment.kind == "comentario").group_by(TicketComment.ticket_id)).all())
        fc = dict(session.exec(select(TicketArchivo.ticket_id, func.count()).where(TicketArchivo.ticket_id.in_(ids)).group_by(TicketArchivo.ticket_id)).all())
    return [_out(t, cc.get(t.id, 0), fc.get(t.id, 0)) for t in rows]


@router.post("/", status_code=201)
def crear(payload: TicketIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    t = Ticket(**payload.model_dump(), created_by=user)
    _apply_status(t, t.status)
    session.add(t)
    session.flush()
    _event(session, t.id, user, "Ticket creado" + (f" y asignado a {t.assignee}" if t.assignee else ""))
    session.commit()
    session.refresh(t)
    return _out(t)


def _detail(session: Session, t: Ticket) -> dict:
    comments = session.exec(select(TicketComment).where(TicketComment.ticket_id == t.id).order_by(TicketComment.id)).all()
    files = session.exec(select(TicketArchivo).where(TicketArchivo.ticket_id == t.id).order_by(TicketArchivo.id)).all()
    out = _out(t, sum(1 for c in comments if c.kind == "comentario"), len(files))
    out["comments"] = [{"id": c.id, "kind": c.kind, "body": c.body, "author": c.author, "created_at": c.created_at.isoformat()} for c in comments]
    out["archivos"] = [_ar_out(a) for a in files]
    return out


@router.get("/{tid}")
def obtener(tid: int, session: Session = Depends(get_session)):
    return _detail(session, _get_or_404(session, tid))


@router.put("/{tid}")
def actualizar(tid: int, payload: TicketIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    t = _get_or_404(session, tid)
    cambios: list[str] = []

    def chg(label: str, old, new) -> None:
        if (old or None) != (new or None):
            cambios.append(f"{label}: {old or '—'} → {new or '—'}")

    chg("Estado", t.status, payload.status)
    chg("Prioridad", t.priority, payload.priority)
    chg("Responsable", t.assignee, payload.assignee)
    chg("Activo", t.asset_tag, payload.asset_tag)
    chg("Solicitante", t.requester_name, payload.requester_name)
    chg("Vence", t.due_date.isoformat() if t.due_date else None, payload.due_date.isoformat() if payload.due_date else None)
    if t.title != payload.title:
        cambios.append("Cambió el título")
    if (t.description or "") != (payload.description or ""):
        cambios.append("Editó la descripción")
    if (t.category or None) != (payload.category or None):
        cambios.append(f"Categoría: {t.category or '—'} → {payload.category or '—'}")
    if not cambios:
        return _detail(session, t)
    _apply_status(t, payload.status)
    for k, v in payload.model_dump().items():
        setattr(t, k, v)
    t.updated_at = _now()
    for c in cambios:
        _event(session, t.id, user, c)
    session.add(t)
    session.commit()
    session.refresh(t)
    return _detail(session, t)


@router.delete("/{tid}", status_code=204)
def eliminar(tid: int, session: Session = Depends(get_session)):
    t = _get_or_404(session, tid)
    for a in session.exec(select(TicketArchivo).where(TicketArchivo.ticket_id == tid)).all():
        (_files_dir() / a.stored_name).unlink(missing_ok=True)
        session.delete(a)
    for c in session.exec(select(TicketComment).where(TicketComment.ticket_id == tid)).all():
        session.delete(c)
    session.delete(t)
    session.commit()


# ------------------------------------------------------------------ comentarios
@router.post("/{tid}/comentarios", status_code=201)
def comentar(tid: int, payload: CommentIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    t = _get_or_404(session, tid)
    c = TicketComment(ticket_id=tid, kind="comentario", body=payload.body, author=user)
    t.updated_at = _now()
    session.add(c)
    session.add(t)
    session.commit()
    session.refresh(c)
    return {"id": c.id, "kind": c.kind, "body": c.body, "author": c.author, "created_at": c.created_at.isoformat()}


@router.delete("/{tid}/comentarios/{cid}", status_code=204)
def borrar_comentario(tid: int, cid: int, session: Session = Depends(get_session)):
    _get_or_404(session, tid)
    c = session.get(TicketComment, cid)
    if not c or c.ticket_id != tid:
        raise HTTPException(404, detail="Comentario no encontrado")
    if c.kind != "comentario":
        raise HTTPException(400, detail="Los eventos del historial no se pueden borrar")
    session.delete(c)
    session.commit()


# ------------------------------------------------------------------ archivos adjuntos (cualquier tipo)
def _files_dir() -> Path:
    d = Path(os.getenv("UPLOADS_DIR", "/app/uploads")) / "_private" / "tickets"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _ar_out(a: TicketArchivo) -> dict:
    return {"id": a.id, "original_name": a.original_name, "content_type": a.content_type, "size": a.size,
            "created_by": a.created_by, "created_at": a.created_at.isoformat()}


def _ar_or_404(session: Session, tid: int, aid: int) -> TicketArchivo:
    a = session.get(TicketArchivo, aid)
    if not a or a.ticket_id != tid:
        raise HTTPException(404, detail="Archivo no encontrado")
    return a


@router.post("/{tid}/archivos", status_code=201)
async def subir_archivos(tid: int, files: list[UploadFile] = File(...), session: Session = Depends(get_session),
                         user: str = Depends(current_user)):
    t = _get_or_404(session, tid)
    ya = session.exec(select(func.count()).select_from(TicketArchivo).where(TicketArchivo.ticket_id == tid)).one()
    if ya + len(files) > MAX_FILES_PER_TICKET:
        raise HTTPException(400, detail=f"Máximo {MAX_FILES_PER_TICKET} archivos por ticket")
    written: list[tuple[Path, str, int, str | None]] = []
    try:
        for f in files:
            name = (f.filename or "archivo").replace("\\", "/").split("/")[-1].strip()[:255] or "archivo"
            path = _files_dir() / uuid.uuid4().hex
            size = 0
            written.append((path, name, 0, None))
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
        a = TicketArchivo(ticket_id=tid, stored_name=path.name, original_name=name, content_type=ctype, size=size, created_by=user)
        session.add(a)
        nuevos.append(a)
        _event(session, tid, user, f"Adjuntó el archivo {name}")
    t.updated_at = _now()
    session.add(t)
    session.commit()
    for a in nuevos:
        session.refresh(a)
    return [_ar_out(a) for a in nuevos]


@router.get("/{tid}/archivos/{aid}/download")
def descargar_archivo(tid: int, aid: int, session: Session = Depends(get_session)):
    a = _ar_or_404(session, tid, aid)
    p = _files_dir() / a.stored_name
    if not p.exists():
        raise HTTPException(404, detail="El archivo ya no está en el servidor")
    return FileResponse(p, filename=a.original_name, media_type=a.content_type or "application/octet-stream")


@router.delete("/{tid}/archivos/{aid}", status_code=204)
def eliminar_archivo(tid: int, aid: int, session: Session = Depends(get_session), user: str = Depends(current_user)):
    t = _get_or_404(session, tid)
    a = _ar_or_404(session, tid, aid)
    (_files_dir() / a.stored_name).unlink(missing_ok=True)
    _event(session, tid, user, f"Eliminó el archivo {a.original_name}")
    t.updated_at = _now()
    session.delete(a)
    session.add(t)
    session.commit()
