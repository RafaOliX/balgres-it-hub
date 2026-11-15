"""Router FastAPI del módulo notas (prefijo /api/notas)."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_
from sqlmodel import Session, SQLModel, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .models import Nota
from .schemas import NotaIn, NotaListItem, NotaRead

router = APIRouter(prefix="/notas", tags=["notas"])


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _snippet(body: str) -> str:
    t = " ".join((body or "").split())
    return t[:160] + ("…" if len(t) > 160 else "")


def _read(n: Nota) -> NotaRead:
    return NotaRead(
        id=n.id, title=n.title, body=n.body or "", tags=list(n.tags or []), asset_tag=n.asset_tag,
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
        stmt = stmt.where(Nota.asset_tag == asset_tag)
    for term in (q or "").split():
        p = f"%{term}%"
        stmt = stmt.where(or_(Nota.title.ilike(p), Nota.body.ilike(p), Nota.asset_tag.ilike(p)))
    rows = session.exec(stmt.order_by(Nota.updated_at.desc()).limit(limit)).all()
    if tag:
        rows = [n for n in rows if tag.lower() in [t.lower() for t in (n.tags or [])]]
    return [
        NotaListItem(
            id=n.id, title=n.title, snippet=_snippet(n.body), tags=list(n.tags or []),
            asset_tag=n.asset_tag, updated_by=n.updated_by, updated_at=n.updated_at,
        )
        for n in rows
    ]


@router.post("/", response_model=NotaRead, status_code=201)
def crear(payload: NotaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = Nota(**payload.model_dump(), created_by=user, updated_by=user)
    session.add(n)
    session.commit()
    session.refresh(n)
    return _read(n)


@router.get("/{nota_id}", response_model=NotaRead)
def obtener(nota_id: int, session: Session = Depends(get_session)):
    return _read(_get_or_404(session, nota_id))


@router.put("/{nota_id}", response_model=NotaRead)
def actualizar(nota_id: int, payload: NotaIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    n = _get_or_404(session, nota_id)
    for k, v in payload.model_dump().items():
        setattr(n, k, v)
    n.updated_by = user
    n.updated_at = _now()
    session.add(n)
    session.commit()
    session.refresh(n)
    return _read(n)


@router.delete("/{nota_id}", status_code=204)
def eliminar(nota_id: int, session: Session = Depends(get_session)):
    session.delete(_get_or_404(session, nota_id))
    session.commit()
