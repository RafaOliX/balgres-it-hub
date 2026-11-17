"""Router FastAPI del módulo planos (prefijo /api/planos)."""
import os
import uuid
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import text
from sqlmodel import Session, SQLModel, func, select

from contacts.common import current_user
from contacts.db import engine, get_session

from .models import Plano, PlanoPin, PlanoTrazo
from .schemas import PinIn, PlanoUpdate, TrazoIn

router = APIRouter(prefix="/planos", tags=["planos"])

MAX_SIZE_BYTES = 10 * 1024 * 1024
EXT_MAP = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}


def _dir() -> Path:
    d = Path(os.getenv("UPLOADS_DIR", "/app/uploads")) / "planos"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _migrate() -> None:
    if engine.dialect.name != "postgresql":
        return  # SQLite: create_all ya crea el esquema completo
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE planos ADD COLUMN IF NOT EXISTS nota_id INTEGER;"))
        conn.execute(text("ALTER TABLE plano_pins ADD COLUMN IF NOT EXISTS nota_id INTEGER;"))


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate()


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


def _pin_out(p: PlanoPin, est: dict, titulos: dict | None = None) -> dict:
    e = est.get(p.asset_tag or "", {})
    return {
        "id": p.id, "x": p.x, "y": p.y, "kind": p.kind, "label": p.label, "asset_tag": p.asset_tag,
        "notes": p.notes, "ip": e.get("ip"), "is_up": e.get("is_up"),
        "nota_id": p.nota_id, "nota_title": (titulos or {}).get(p.nota_id) if p.nota_id else None,
    }


def _plano_out(p: Plano, pins: list[dict] | None = None, pin_count: int | None = None, titulos: dict | None = None) -> dict:
    out = {
        "id": p.id, "name": p.name, "notes": p.notes, "filename": p.filename, "width": p.width, "height": p.height,
        "created_by": p.created_by, "updated_at": p.updated_at.isoformat(),
        "nota_id": p.nota_id, "nota_title": (titulos or {}).get(p.nota_id) if p.nota_id else None,
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
    ids = {x.nota_id for x in pins if x.nota_id} | ({p.nota_id} if p.nota_id else set())
    titulos = _titulos_notas(session, ids)
    trazos = session.exec(select(PlanoTrazo).where(PlanoTrazo.plano_id == plano_id).order_by(PlanoTrazo.id)).all()
    out = _plano_out(p, pins=[_pin_out(x, est, titulos) for x in pins], titulos=titulos)
    out["trazos"] = [_trazo_out(t) for t in trazos]
    return out


@router.put("/{plano_id}")
def actualizar(plano_id: int, payload: PlanoUpdate, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    _check_nota(session, payload.nota_id)
    p.name, p.notes, p.nota_id, p.updated_at = payload.name, payload.notes, payload.nota_id, _now()
    session.add(p)
    session.commit()
    session.refresh(p)
    return _plano_out(p)


@router.delete("/{plano_id}", status_code=204)
def eliminar(plano_id: int, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    for x in session.exec(select(PlanoPin).where(PlanoPin.plano_id == plano_id)).all():
        session.delete(x)
    for t in session.exec(select(PlanoTrazo).where(PlanoTrazo.plano_id == plano_id)).all():
        session.delete(t)
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
    _check_nota(session, payload.nota_id)
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
    _check_nota(session, payload.nota_id)
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


# ------------------------------------------------------------------ vínculo con notas (sin FK; notas es opcional)
def _check_nota(session: Session, nota_id: int | None) -> None:
    if nota_id is None:
        return
    try:
        from notas.models import Nota
    except ImportError:
        return
    if session.get(Nota, nota_id) is None:
        raise HTTPException(404, detail="Nota no encontrada")


def _titulos_notas(session: Session, ids: set[int]) -> dict[int, str]:
    if not ids:
        return {}
    try:
        from notas.models import Nota
    except ImportError:
        return {}
    return {n.id: n.title for n in session.exec(select(Nota).where(Nota.id.in_(list(ids)))).all()}


@router.get("/by-nota/{nota_id}")
def por_nota(nota_id: int, session: Session = Depends(get_session)):
    """Planos que enlazan a una nota (el plano entero o alguno de sus pines). Lo consume el módulo notas."""
    out: dict[int, dict] = {}
    for p in session.exec(select(Plano).where(Plano.nota_id == nota_id)).all():
        out[p.id] = {"id": p.id, "name": p.name, "plano": True, "pins": []}
    pins = session.exec(select(PlanoPin).where(PlanoPin.nota_id == nota_id)).all()
    if pins:
        planos = {p.id: p for p in session.exec(select(Plano).where(Plano.id.in_(list({x.plano_id for x in pins})))).all()}
        for x in pins:
            p = planos.get(x.plano_id)
            if p is None:
                continue
            d = out.setdefault(p.id, {"id": p.id, "name": p.name, "plano": False, "pins": []})
            d["pins"].append(x.label or x.kind)
    return sorted(out.values(), key=lambda d: d["name"].lower())


# ------------------------------------------------------------------ trazos (dibujo libre y flechas)
MAX_TRAZOS = 2000


def _trazo_out(t: PlanoTrazo) -> dict:
    return {"id": t.id, "kind": t.kind, "color": t.color, "width": t.width, "points": t.points or []}


@router.post("/{plano_id}/trazos", status_code=201)
def crear_trazo(plano_id: int, payload: TrazoIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    p = _get_or_404(session, plano_id)
    n = session.exec(select(func.count()).select_from(PlanoTrazo).where(PlanoTrazo.plano_id == plano_id)).one()
    if n >= MAX_TRAZOS:
        raise HTTPException(400, detail=f"Este plano ya tiene {MAX_TRAZOS} trazos. Borra algunos antes de seguir.")
    t = PlanoTrazo(plano_id=plano_id, created_by=user, **payload.model_dump())
    p.updated_at = _now()
    session.add(t)
    session.add(p)
    session.commit()
    session.refresh(t)
    return _trazo_out(t)


@router.delete("/{plano_id}/trazos/{trazo_id}", status_code=204)
def eliminar_trazo(plano_id: int, trazo_id: int, session: Session = Depends(get_session)):
    p = _get_or_404(session, plano_id)
    t = session.get(PlanoTrazo, trazo_id)
    if not t or t.plano_id != plano_id:
        raise HTTPException(404, detail="Trazo no encontrado")
    p.updated_at = _now()
    session.delete(t)
    session.add(p)
    session.commit()


@router.delete("/{plano_id}/trazos", status_code=204)
def limpiar_trazos(plano_id: int, session: Session = Depends(get_session)):
    """Borra TODO el dibujo del plano (los pines no se tocan)."""
    p = _get_or_404(session, plano_id)
    for t in session.exec(select(PlanoTrazo).where(PlanoTrazo.plano_id == plano_id)).all():
        session.delete(t)
    p.updated_at = _now()
    session.add(p)
    session.commit()
