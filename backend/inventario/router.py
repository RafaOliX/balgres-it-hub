"""Router FastAPI del módulo inventario."""
import os
import uuid
from pathlib import Path
from io import BytesIO

import pandas as pd
from fpdf import FPDF
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import StreamingResponse
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .db import apply_migrations, engine, get_session
from .models import ItAsset, ItAssetImage, ItAssetHistory
from .schemas import ItAssetCreate, ItAssetHistoryRead, ItAssetImageRead, ItAssetRead, ItAssetUpdate

router = APIRouter(prefix="/inventario", tags=["inventario"])

UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIZE_BYTES = 5 * 1024 * 1024
MAX_IMAGES_PER_ASSET = 20
EXT_MAP = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    apply_migrations()

def _get_or_404(session: Session, tag: str) -> ItAsset:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == tag)).first()
    if asset is None:
        raise HTTPException(404, detail=f"No existe activo con tag '{tag}'")
    return asset

def _log_change(session: Session, asset_id: int, field: str, old: str | None, new: str | None):
    if old == new: return
    h = ItAssetHistory(
        asset_id=asset_id, field_name=field,
        old_value=str(old) if old is not None else None,
        new_value=str(new) if new is not None else None,
        changed_by="admin",
    )
    session.add(h)

@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}

@router.get("/", response_model=list[ItAssetRead])
def listar(session: Session = Depends(get_session)) -> list[ItAsset]:
    return list(session.exec(select(ItAsset)).all())

@router.get("/buscar", response_model=list[ItAssetRead])
def buscar(q: str = Query(..., min_length=1), session: Session = Depends(get_session)) -> list[ItAsset]:
    pattern = f"%{q}%"
    stmt = select(ItAsset).where(
        ItAsset.asset_tag.ilike(pattern) | ItAsset.category.ilike(pattern)
        | ItAsset.brand.ilike(pattern) | ItAsset.model.ilike(pattern)
        | ItAsset.serial_number.ilike(pattern) | ItAsset.location.ilike(pattern)
    )
    return list(session.exec(stmt).all())

@router.post("/", response_model=ItAssetRead, status_code=status.HTTP_201_CREATED)
def crear(payload: ItAssetCreate, session: Session = Depends(get_session)) -> ItAsset:
    asset = ItAsset(**payload.model_dump())
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="asset_tag o serial_number ya existen") from None
    session.refresh(asset)
    _log_change(session, asset.id, "CREATED", None, asset.asset_tag)
    session.commit()
    session.refresh(asset)
    return asset

@router.get("/export")
def exportar_excel(session: Session = Depends(get_session)):
    assets = session.exec(select(ItAsset)).all()
    data = []
    for a in assets:
        data.append({
            "Tag": a.asset_tag, "Categoría": a.category, "Marca": a.brand,
            "Modelo": a.model, "S/N": a.serial_number, "Cantidad": a.quantity,
            "Unidad": a.unit, "Ubicación": a.location, "Estado": a.status, "Notas": a.notes
        })
    df = pd.DataFrame(data)
    output = BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Inventario')
    output.seek(0)
    return StreamingResponse(
        output, 
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
        headers={"Content-Disposition": "attachment; filename=inventario.xlsx"}
    )

@router.get("/{asset_tag}", response_model=ItAssetRead)
def obtener(asset_tag: str, session: Session = Depends(get_session)) -> ItAsset:
    return _get_or_404(session, asset_tag)

@router.get("/{asset_tag}/pdf")
def generar_pdf(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=16, style='B')
    pdf.cell(200, 10, txt="Acta de Recepción de Equipo TI", ln=True, align='C')
    
    pdf.set_font("Arial", size=12)
    pdf.ln(10)
    pdf.cell(200, 10, txt=f"Tag: {asset.asset_tag}", ln=True)
    pdf.cell(200, 10, txt=f"Equipo: {asset.category} {asset.brand} {asset.model}", ln=True)
    pdf.cell(200, 10, txt=f"Serial: {asset.serial_number}", ln=True)
    pdf.cell(200, 10, txt=f"Cantidad: {asset.quantity} {asset.unit}", ln=True)
    pdf.cell(200, 10, txt=f"Estado: {asset.status}", ln=True)
    
    pdf.ln(30)
    pdf.cell(90, 10, txt="_________________________", ln=False)
    pdf.cell(100, 10, txt="_________________________", ln=True)
    pdf.cell(90, 10, txt="Firma Responsable TI", ln=False)
    pdf.cell(100, 10, txt="Firma de Recibido", ln=True)
    
    pdf_output = pdf.output(dest="S").encode("latin-1")
    return StreamingResponse(
        BytesIO(pdf_output), 
        media_type="application/pdf", 
        headers={"Content-Disposition": f"attachment; filename=acta_{asset.asset_tag}.pdf"}
    )

@router.patch("/{asset_tag}", response_model=ItAssetRead)
def actualizar(asset_tag: str, payload: ItAssetUpdate, session: Session = Depends(get_session)) -> ItAsset:
    asset = _get_or_404(session, asset_tag)
    update_data = payload.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        old = getattr(asset, k)
        if old != v:
            _log_change(session, asset.id, k, str(old) if old else None, str(v) if v else None)
            setattr(asset, k, v)
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="El nuevo tag o S/N ya existen en otro activo") from None
    session.refresh(asset)
    return asset

@router.get("/{asset_tag}/history", response_model=list[ItAssetHistoryRead])
def historial(asset_tag: str, session: Session = Depends(get_session)) -> list[ItAssetHistory]:
    asset = _get_or_404(session, asset_tag)
    stmt = select(ItAssetHistory).where(ItAssetHistory.asset_id == asset.id).order_by(ItAssetHistory.changed_at.desc())
    return list(session.exec(stmt).all())

@router.delete("/{asset_tag}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar(asset_tag: str, session: Session = Depends(get_session)) -> None:
    asset = _get_or_404(session, asset_tag)
    for img in asset.images:
        p = UPLOADS_DIR / img.filename
        if p.exists(): p.unlink()
    session.delete(asset)
    session.commit()

# ──────────────── Imágenes ────────────────
@router.post("/{asset_tag}/images", response_model=list[ItAssetImageRead], status_code=status.HTTP_201_CREATED)
async def subir_imagenes(asset_tag: str, files: list[UploadFile] = File(...), session: Session = Depends(get_session)) -> list[ItAssetImage]:
    asset = _get_or_404(session, asset_tag)
    if len(asset.images) + len(files) > MAX_IMAGES_PER_ASSET:
        raise HTTPException(400, detail=f"Máximo {MAX_IMAGES_PER_ASSET} imágenes")
    nuevas: list[ItAssetImage] = []
    for f in files:
        if f.content_type not in ALLOWED_TYPES:
            raise HTTPException(400, detail=f"Tipo no permitido: {f.content_type}")
        try:
            content = await f.read()
            filename = f"{uuid.uuid4().hex}.{EXT_MAP[f.content_type]}"
            (UPLOADS_DIR / filename).write_bytes(content)
            img = ItAssetImage(asset_id=asset.id, filename=filename)
            session.add(img)
            nuevas.append(img)
        except Exception as e:
            session.rollback()
            raise HTTPException(500, detail=f"Error: {str(e)}")
    try:
        session.commit()
        for img in nuevas: session.refresh(img)
        return nuevas
    except Exception as e:
        session.rollback()
        raise HTTPException(500, detail=f"DB Error: {str(e)}")

@router.delete("/{asset_tag}/images/{image_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_imagen(asset_tag: str, image_id: int, session: Session = Depends(get_session)) -> None:
    asset = _get_or_404(session, asset_tag)
    img = session.get(ItAssetImage, image_id)
    if img is None or img.asset_id != asset.id:
        raise HTTPException(404, detail="Imagen no encontrada")
    p = UPLOADS_DIR / img.filename
    if p.exists(): p.unlink()
    session.delete(img)
    session.commit()
