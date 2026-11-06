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
from .models import ItAsset, ItAssetImage, ItAssetHistory, Category
from .schemas import ItAssetCreate, ItAssetHistoryRead, ItAssetImageRead, ItAssetRead, ItAssetUpdate, CategoryCreate, CategoryRead

router = APIRouter(prefix="/inventario", tags=["inventario"])

UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIZE_BYTES = 5 * 1024 * 1024
EXT_MAP = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}

def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    apply_migrations()

def _get_or_404(session: Session, tag: str) -> ItAsset:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == tag)).first()
    if asset is None: raise HTTPException(404, detail=f"No existe activo con tag '{tag}'")
    return asset

def _log_change(session: Session, asset_id: int, field: str, old: str | None, new: str | None):
    if old == new: return
    session.add(ItAssetHistory(asset_id=asset_id, field_name=field, old_value=str(old) if old else None, new_value=str(new) if new else None))

# ==============================================================================
# RUTAS FIJAS (DEBEN IR PRIMERO PARA EVITAR QUE /{asset_tag} LAS ATRAPE)
# ==============================================================================

@router.get("/health")
async def health() -> dict[str, str]: return {"module": "inventario", "status": "ok"}

@router.get("/categories", response_model=list[CategoryRead])
def listar_categorias(session: Session = Depends(get_session)):
    return list(session.exec(select(Category)).all())

@router.post("/categories", response_model=CategoryRead, status_code=201)
def crear_categoria(payload: CategoryCreate, session: Session = Depends(get_session)):
    cat = Category(**payload.model_dump())
    session.add(cat)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="La categoría ya existe")
    session.refresh(cat)
    return cat

@router.put("/categories/{cat_id}", response_model=CategoryRead)
def actualizar_categoria(cat_id: int, payload: CategoryCreate, session: Session = Depends(get_session)):
    cat = session.get(Category, cat_id)
    if not cat: raise HTTPException(404, detail="Categoría no encontrada")
    for k, v in payload.model_dump().items():
        setattr(cat, k, v)
    session.add(cat)
    session.commit()
    session.refresh(cat)
    return cat

@router.delete("/categories/{cat_id}", status_code=204)
def eliminar_categoria(cat_id: int, session: Session = Depends(get_session)):
    cat = session.get(Category, cat_id)
    if not cat: raise HTTPException(404, detail="Categoría no encontrada")
    activos = session.exec(select(ItAsset).where(ItAsset.category_id == cat_id)).first()
    if activos: raise HTTPException(400, detail="No se puede eliminar, hay activos usando esta categoría")
    session.delete(cat)
    session.commit()

@router.get("/siguiente-tag")
def get_siguiente_tag(category_id: int, session: Session = Depends(get_session)):
    cat = session.get(Category, category_id)
    if not cat: raise HTTPException(404, detail="Categoría no encontrada")
    prefijo = cat.prefix.upper()
    stmt = select(ItAsset.asset_tag).where(ItAsset.asset_tag.like(f"{prefijo}-%")).order_by(ItAsset.asset_tag.desc())
    ultimo_tag = session.exec(stmt).first()
    if ultimo_tag:
        try:
            num = int(ultimo_tag.split('-')[1]) + 1
            return {"tag": f"{prefijo}-{num:03d}"}
        except: pass
    return {"tag": f"{prefijo}-001"}

@router.get("/export")
def exportar_excel(session: Session = Depends(get_session)):
    assets = session.exec(select(ItAsset)).all()
    data = [{"Tag": a.asset_tag, "Categoría": a.category, "Marca": a.brand, "Modelo": a.model, "S/N": a.serial_number, "Cantidad": a.quantity, "Unidad": a.unit, "Ubicación": a.location, "Estado": a.status, "Asignado a": a.assigned_to, "Notas": a.notes} for a in assets]
    df = pd.DataFrame(data)
    output = BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer: df.to_excel(writer, index=False, sheet_name='Inventario')
    output.seek(0)
    return StreamingResponse(output, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": "attachment; filename=inventario.xlsx"})

@router.get("/buscar", response_model=list[ItAssetRead])
def buscar(q: str, session: Session = Depends(get_session)):
    pattern = f"%{q}%"
    stmt = select(ItAsset).where(ItAsset.asset_tag.ilike(pattern) | ItAsset.category.ilike(pattern) | ItAsset.brand.ilike(pattern) | ItAsset.model.ilike(pattern) | ItAsset.serial_number.ilike(pattern))
    return list(session.exec(stmt).all())

@router.get("/", response_model=list[ItAssetRead])
def listar(session: Session = Depends(get_session)): return list(session.exec(select(ItAsset)).all())

@router.post("/", response_model=ItAssetRead, status_code=201)
def crear(payload: ItAssetCreate, session: Session = Depends(get_session)):
    asset = ItAsset(**payload.model_dump())
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="Tag o S/N ya existen")
    session.refresh(asset)
    return asset

# ==============================================================================
# RUTAS DINÁMICAS (DEBEN IR AL FINAL)
# ==============================================================================

@router.get("/{asset_tag}", response_model=ItAssetRead)
def obtener(asset_tag: str, session: Session = Depends(get_session)): 
    return _get_or_404(session, asset_tag)

@router.patch("/{asset_tag}", response_model=ItAssetRead)
def actualizar(asset_tag: str, payload: ItAssetUpdate, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    for k, v in payload.model_dump(exclude_unset=True).items():
        _log_change(session, asset.id, k, getattr(asset, k), v)
        setattr(asset, k, v)
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="El nuevo tag o S/N ya existen")
    session.refresh(asset)
    return asset

@router.get("/{asset_tag}/history", response_model=list[ItAssetHistoryRead])
def historial(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    return list(session.exec(select(ItAssetHistory).where(ItAssetHistory.asset_id == asset.id).order_by(ItAssetHistory.changed_at.desc())).all())

@router.delete("/{asset_tag}", status_code=204)
def eliminar(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    for img in asset.images:
        p = UPLOADS_DIR / img.filename
        if p.exists(): p.unlink()
    session.delete(asset)
    session.commit()

@router.post("/{asset_tag}/images", response_model=list[ItAssetImageRead], status_code=201)
async def subir_imagenes(asset_tag: str, files: list[UploadFile] = File(...), session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    nuevas = []
    for f in files:
        content = await f.read()
        filename = f"{uuid.uuid4().hex}.{EXT_MAP.get(f.content_type, 'jpg')}"
        (UPLOADS_DIR / filename).write_bytes(content)
        img = ItAssetImage(asset_id=asset.id, filename=filename)
        session.add(img)
        nuevas.append(img)
    session.commit()
    for img in nuevas: session.refresh(img)
    return nuevas

@router.delete("/{asset_tag}/images/{image_id}", status_code=204)
def eliminar_imagen(asset_tag: str, image_id: int, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    img = session.get(ItAssetImage, image_id)
    if img and img.asset_id == asset.id:
        p = UPLOADS_DIR / img.filename
        if p.exists(): p.unlink()
        session.delete(img)
        session.commit()

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
    pdf.cell(200, 10, txt=f"Serial: {asset.serial_number or 'N/A'}", ln=True)
    pdf.cell(200, 10, txt=f"Cantidad: {asset.quantity} {asset.unit}", ln=True)
    pdf.cell(200, 10, txt=f"Estado: {asset.status}", ln=True)
    pdf.ln(10)
    pdf.cell(200, 10, txt=f"Asignado a: {asset.assigned_to or 'No asignado'}", ln=True)
    pdf.ln(30)
    pdf.cell(90, 10, txt="_________________________", ln=False)
    pdf.cell(100, 10, txt="_________________________", ln=True)
    pdf.cell(90, 10, txt="Firma Responsable TI", ln=False)
    pdf.cell(100, 10, txt="Firma de Recibido", ln=True)
    pdf_output = pdf.output(dest="S").encode("latin-1")
    return StreamingResponse(BytesIO(pdf_output), media_type="application/pdf", headers={"Content-Disposition": f"attachment; filename=acta_{asset.asset_tag}.pdf"})
