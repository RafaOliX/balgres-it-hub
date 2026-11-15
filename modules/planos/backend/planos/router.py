"""Router FastAPI del módulo planos (prefijo /api/planos)."""
import os
import uuid
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlmodel import Session, SQLModel, func, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .models import Plano, PlanoPin
from .schemas import PinIn, PlanoUpdate

router = APIRouter(prefix="/planos", tags=["planos"])

MAX_SIZE_BYTES = 10 * 1024 * 1024
EXT_MAP = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}


def _dir() -> Path:
    d = Path(os.getenv("UPLOADS_DIR", "/app/uploads")) / "planos"
    d.mkdir(parents=True, exist_ok=True)
    return d


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _get_or_404(session: Session, plano_id: int) -> Plano:
    p = session.get(Plano, plano_id)
    if not p:
        raise HTTPException(404, detail="Plano no encontrado")
    return p


def _estados(session: Session, tags: set[str]) -> dict[str, dict]:
    """Estado en línea desde redes (si está instalado). Sin redes: todo 'desconocido'."""
    if not tags:
        return {}
    try:
        from redes.models import IpAddress
    except ImportError:
        return {}
    return {
        r.asset_tag: {"ip": r.ip, "is_up": r.is_up}
        for r in session.exec(select(IpAddress).where(IpAddress.asset_tag.in_(tags))).all()
    }


def _pin_out(p: PlanoPin, est: dict) -> dict:
    e = est.get(p.asset_tag or "", {})
    return {
        "id": p.id, "x": p.x, "y": p.y, "kind": p.kind, "label": p.label, "asset_tag": p.asset_tag,
        "notes": p.notes, "ip": e.get("ip"), "is_up": e.get("is_up"),
    }


def _plano_out(p: Plano, pins: list[dict] | None = None, pin_count: int | None = None) -> dict:
    out = {
        "id": p.id, "name": p.name, "notes": p.notes, "filename": p.filename, "width": p.width, "height": p.height,
        "created_by": p.created_by, "updated_at": p.updated_at.isoformat(),
        "pin_count": pin_count if pin_count is not None else len(pins or []),
    }
    if pins is not None:
        out["pins"] = pins
    return out


# IMPORTANTE: /health va antes que /{plano_id}
@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "planos", "status": "ok"}


@router.get("/")
def listar(session: Session = Depends(get_session)):
    counts = {pid: n for pid, n in session.exec(select(PlanoPin.plano_id, func.count()).group_by(PlanoPin.plano_id)).all()}
    rows = session.exec(select(Plano).order_by(Plano.updated_at.desc())).all()
    return [_plano_out(p, pin_count=counts.get(p.id, 0)) for p in rows]


@router.post("/", status_code=201)
async def crear(
    name: str = Form(...),
    notes: str = Form(""),
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    user: str = Depends(current_user),
):
    name = " ".join(name.split())
    if not name:
        raise HTTPException(422, detail="El nombre es obligatorio")
    content = await file.read()
    if len(content) > MAX_SIZE_BYTES:
        raise HTTPException(413, detail=f"La imagen supera {MAX_SIZE_BYTES // (1024 * 1024)} MB")
    fmt, w, h = "", 0, 0
    try:
        from PIL import Image
        with Image.open(BytesIO(content)) as im:
            fmt = (im.format or "").upper()
            w, h = im.size
            im.verify()
    except Exception:
        raise HTTPException(415, detail="El archivo no es una imagen válida.")
    ext = EXT_MAP.get(fmt)
    if ext is None or w <= 0 or h <= 0:
        raise HTTPException(415, detail="Formato no permitido. Usa JPG, PNG o WEBP.")
    filename = f"{uuid.uuid4().hex}.{ext}"
    (_dir() / filename).write_bytes(content)
    p = Plano(name=name, notes=notes.strip() or None, filename=filename, width=w, height=h, created_by=user)
    session.add(p)
    session.commit()
    session.refresh(p)
    return _plano_out(p, pins=[])


@router.get("/{plano_id}")
def obtener(plano_id: int, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    pins = session.exec(select(PlanoPin).where(PlanoPin.plano_id == plano_id).order_by(PlanoPin.id)).all()
    est = _estados(session, {x.asset_tag for x in pins if x.asset_tag})
    return _plano_out(p, pins=[_pin_out(x, est) for x in pins])


@router.put("/{plano_id}")
def actualizar(plano_id: int, payload: PlanoUpdate, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    p.name, p.notes, p.updated_at = payload.name, payload.notes, _now()
    session.add(p)
    session.commit()
    session.refresh(p)
    return _plano_out(p)


@router.delete("/{plano_id}", status_code=204)
def eliminar(plano_id: int, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    for x in session.exec(select(PlanoPin).where(PlanoPin.plano_id == plano_id)).all():
        session.delete(x)
    (_dir() / p.filename).unlink(missing_ok=True)
    session.delete(p)
    session.commit()


# ------------------------------------------------------------------ pines
def _pin_or_404(session: Session, plano_id: int, pin_id: int) -> PlanoPin:
    x = session.get(PlanoPin, pin_id)
    if not x or x.plano_id != plano_id:
        raise HTTPException(404, detail="Pin no encontrado")
    return x


@router.post("/{plano_id}/pins", status_code=201)
def crear_pin(plano_id: int, payload: PinIn, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    x = PlanoPin(plano_id=plano_id, **payload.model_dump())
    p.updated_at = _now()
    session.add(x)
    session.add(p)
    session.commit()
    session.refresh(x)
    return _pin_out(x, _estados(session, {x.asset_tag} if x.asset_tag else set()))


@router.put("/{plano_id}/pins/{pin_id}")
def actualizar_pin(plano_id: int, pin_id: int, payload: PinIn, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    x = _pin_or_404(session, plano_id, pin_id)
    for k, v in payload.model_dump().items():
        setattr(x, k, v)
    p.updated_at = _now()
    session.add(x)
    session.add(p)
    session.commit()
    session.refresh(x)
    return _pin_out(x, _estados(session, {x.asset_tag} if x.asset_tag else set()))


@router.delete("/{plano_id}/pins/{pin_id}", status_code=204)
def eliminar_pin(plano_id: int, pin_id: int, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    x = _pin_or_404(session, plano_id, pin_id)
    p.updated_at = _now()
    session.delete(x)
    session.add(p)
    session.commit()
