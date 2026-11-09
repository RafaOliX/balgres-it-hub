"""Router FastAPI del módulo inventario."""
import os
import re
import uuid
from datetime import date, datetime, timezone
from io import BytesIO
from pathlib import Path

import pandas as pd
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from fpdf import FPDF
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .catalogos import router as catalogos_router
from .common import current_user, location_paths
from .db import apply_migrations, engine, get_session
from .models import Category, Employee, ItAsset, ItAssetAssignment, ItAssetHistory, ItAssetImage
from .schemas import (
    AssignmentRead,
    AssignRequest,
    CategoryCreate,
    CategoryRead,
    ItAssetCreate,
    ItAssetHistoryRead,
    ItAssetImageRead,
    ItAssetRead,
    ItAssetUpdate,
    ReturnRequest,
)

router = APIRouter(prefix="/inventario", tags=["inventario"])

UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIZE_BYTES = 5 * 1024 * 1024
EXT_MAP = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
NOT_NULL_FIELDS = {"asset_tag", "category", "brand", "model", "quantity", "is_draft"}


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    apply_migrations()


# ------------------------------------------------------------------ helpers
def _get_or_404(session: Session, tag: str, include_deleted: bool = False) -> ItAsset:
    stmt = select(ItAsset).where(ItAsset.asset_tag == tag)
    if not include_deleted:
        stmt = stmt.where(ItAsset.deleted_at.is_(None))
    asset = session.exec(stmt).first()
    if asset is None:
        raise HTTPException(404, detail=f"No existe activo con tag '{tag}'")
    return asset


def _s(v) -> str | None:
    return None if v is None else str(v)


def _log_change(session: Session, asset_id: int, field: str, old, new, user: str = "admin") -> None:
    if _s(old) == _s(new):
        return
    session.add(ItAssetHistory(asset_id=asset_id, field_name=field, old_value=_s(old), new_value=_s(new), changed_by=user))


def _clean(v) -> str | None:
    if v is None or (not isinstance(v, str) and pd.isna(v)):
        return None
    v = str(v).strip()
    return v or None


def _date(v):
    v = _clean(v)
    if not v:
        return None
    try:
        return pd.to_datetime(v).date()
    except Exception:
        return None


def _float(v):
    v = _clean(v)
    if not v:
        return None
    try:
        return float(v.replace(",", "."))
    except ValueError:
        return None


def _validate_sn(session: Session, asset: ItAsset) -> None:
    if asset.is_draft or not asset.category_id:
        return
    cat = session.get(Category, asset.category_id)
    if cat and cat.requires_sn and not (asset.serial_number or "").strip():
        raise HTTPException(422, detail=f"La categoría '{cat.name}' requiere Número de Serie (S/N).")


def _next_tag(session: Session, prefix: str) -> str:
    prefix = prefix.upper()
    tags = session.exec(select(ItAsset.asset_tag).where(ItAsset.asset_tag.like(f"{prefix}-%"))).all()
    pat = re.compile(rf"^{re.escape(prefix)}-(\d+)$")
    nums = [int(m.group(1)) for t in tags if (m := pat.match(t))]
    return f"{prefix}-{(max(nums) if nums else 0) + 1:03d}"


def _check_category(session: Session, payload: CategoryCreate, cat_id: int | None = None) -> str:
    prefix = payload.prefix.strip().upper()
    dup = session.exec(select(Category).where(Category.prefix == prefix)).first()
    if dup and dup.id != cat_id:
        raise HTTPException(409, detail=f"El prefijo '{prefix}' ya lo usa la categoría '{dup.name}'")
    if payload.parent_id is not None:
        if payload.parent_id == cat_id:
            raise HTTPException(400, detail="Una categoría no puede ser su propio padre")
        if not session.get(Category, payload.parent_id):
            raise HTTPException(404, detail="Categoría padre no encontrada")
    return prefix


def _resolve_location(session: Session, location_id: int | None) -> str | None:
    if location_id is None:
        return None
    paths = location_paths(session)
    if location_id not in paths:
        raise HTTPException(404, detail="Ubicación no encontrada")
    return paths[location_id]


def _latin(s) -> str:
    return str(s).encode("latin-1", "replace").decode("latin-1")


def _qr_png(text: str) -> BytesIO:
    try:
        import segno
    except ImportError:
        raise HTTPException(501, detail="Falta la dependencia 'segno' en el backend (agrégala al pyproject del módulo).")
    buf = BytesIO()
    segno.make(text, error="m").save(buf, kind="png", scale=8, border=1)
    buf.seek(0)
    return buf


# ==============================================================================
# RUTAS FIJAS (DEBEN IR PRIMERO PARA EVITAR QUE /{asset_tag} LAS ATRAPE)
# ==============================================================================
@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}


# /locations, /employees, /dashboard
router.include_router(catalogos_router)


# ---- categorías
@router.get("/categories", response_model=list[CategoryRead])
def listar_categorias(session: Session = Depends(get_session)):
    return list(session.exec(select(Category).order_by(Category.name)).all())


@router.post("/categories", response_model=CategoryRead, status_code=201)
def crear_categoria(payload: CategoryCreate, session: Session = Depends(get_session)):
    prefix = _check_category(session, payload)
    cat = Category(**{**payload.model_dump(), "prefix": prefix})
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
    if not cat:
        raise HTTPException(404, detail="Categoría no encontrada")
    prefix = _check_category(session, payload, cat_id)
    renombrada = cat.name != payload.name
    for k, v in payload.model_dump().items():
        setattr(cat, k, v)
    cat.prefix = prefix
    session.add(cat)
    if renombrada:
        for a in session.exec(select(ItAsset).where(ItAsset.category_id == cat_id)).all():
            a.category = cat.name
            session.add(a)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="Ya existe una categoría con ese nombre")
    session.refresh(cat)
    return cat


@router.delete("/categories/{cat_id}", status_code=204)
def eliminar_categoria(cat_id: int, session: Session = Depends(get_session)):
    cat = session.get(Category, cat_id)
    if not cat:
        raise HTTPException(404, detail="Categoría no encontrada")
    if session.exec(select(Category).where(Category.parent_id == cat_id)).first():
        raise HTTPException(400, detail="No se puede eliminar: tiene subcategorías")
    if session.exec(select(ItAsset).where(ItAsset.category_id == cat_id)).first():
        raise HTTPException(400, detail="No se puede eliminar, hay activos usando esta categoría")
    session.delete(cat)
    session.commit()


@router.get("/siguiente-tag")
def get_siguiente_tag(category_id: int, session: Session = Depends(get_session)):
    cat = session.get(Category, category_id)
    if not cat:
        raise HTTPException(404, detail="Categoría no encontrada")
    return {"tag": _next_tag(session, cat.prefix)}


# ---- excel
EXPORT_COLS = [
    "Tag", "Categoría", "Marca", "Modelo", "S/N", "Cantidad", "Unidad", "Ubicación", "Estado",
    "Asignado a", "Notas", "Fecha compra", "Costo", "Proveedor", "Factura", "Garantía hasta",
]


@router.get("/export")
def exportar_excel(session: Session = Depends(get_session)):
    assets = session.exec(
        select(ItAsset).where(ItAsset.is_draft == False, ItAsset.deleted_at.is_(None)).order_by(ItAsset.asset_tag)  # noqa: E712
    ).all()
    data = [
        {
            "Tag": a.asset_tag, "Categoría": a.category, "Marca": a.brand, "Modelo": a.model,
            "S/N": a.serial_number, "Cantidad": a.quantity, "Unidad": a.unit, "Ubicación": a.location,
            "Estado": a.status, "Asignado a": a.assigned_to, "Notas": a.notes,
            "Fecha compra": a.purchase_date, "Costo": a.cost, "Proveedor": a.supplier,
            "Factura": a.invoice_number, "Garantía hasta": a.warranty_until,
        }
        for a in assets
    ]
    df = pd.DataFrame(data, columns=EXPORT_COLS)
    output = BytesIO()
    with pd.ExcelWriter(output, engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name="Inventario")
    output.seek(0)
    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=inventario.xlsx"},
    )


@router.post("/import")
async def importar_excel(file: UploadFile = File(...), session: Session = Depends(get_session)):
    try:
        df = pd.read_excel(BytesIO(await file.read()), dtype=str)
    except Exception:
        raise HTTPException(400, detail="No se pudo leer el archivo. Debe ser un .xlsx válido.")
    faltan = {"Tag", "Categoría", "Marca", "Modelo"} - set(df.columns)
    if faltan:
        raise HTTPException(400, detail=f"Faltan columnas obligatorias: {', '.join(sorted(faltan))}")

    cats = {c.name.lower(): c for c in session.exec(select(Category)).all()}
    existentes = set(session.exec(select(ItAsset.asset_tag)).all())
    creados, omitidos, errores = 0, 0, []

    for i, row in df.iterrows():
        fila = int(i) + 2
        tag, cat_name = _clean(row.get("Tag")), _clean(row.get("Categoría"))
        brand, model = _clean(row.get("Marca")), _clean(row.get("Modelo"))
        if not (tag and cat_name and brand and model):
            errores.append({"fila": fila, "detalle": "Tag, Categoría, Marca y Modelo son obligatorios"})
            continue
        if tag in existentes:
            omitidos += 1
            continue
        cat = cats.get(cat_name.lower())
        if not cat:
            errores.append({"fila": fila, "detalle": f"La categoría '{cat_name}' no existe"})
            continue
        try:
            qty = int(float(_clean(row.get("Cantidad")) or 1))
        except ValueError:
            errores.append({"fila": fila, "detalle": "Cantidad inválida"})
            continue
        session.add(ItAsset(
            asset_tag=tag, category=cat.name, category_id=cat.id, brand=brand, model=model,
            serial_number=_clean(row.get("S/N")), quantity=qty,
            unit=_clean(row.get("Unidad")) or cat.unit, location=_clean(row.get("Ubicación")),
            status=_clean(row.get("Estado")) or "Operativo",
            assigned_to=_clean(row.get("Asignado a")), notes=_clean(row.get("Notas")),
            purchase_date=_date(row.get("Fecha compra")), cost=_float(row.get("Costo")),
            supplier=_clean(row.get("Proveedor")), invoice_number=_clean(row.get("Factura")),
            warranty_until=_date(row.get("Garantía hasta")),
        ))
        existentes.add(tag)
        creados += 1

    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="Error de integridad al importar. No se guardó nada.")
    return {"creados": creados, "omitidos": omitidos, "errores": errores}


# ---- etiquetas QR (PDF A4, 3 x 7 por página)
@router.get("/labels")
def etiquetas(tags: str | None = None, session: Session = Depends(get_session)):
    stmt = select(ItAsset).where(ItAsset.deleted_at.is_(None), ItAsset.is_draft == False)  # noqa: E712
    if tags:
        lista = [t.strip() for t in tags.split(",") if t.strip()]
        stmt = stmt.where(ItAsset.asset_tag.in_(lista))
    assets = session.exec(stmt.order_by(ItAsset.asset_tag)).all()
    if not assets:
        raise HTTPException(404, detail="No hay activos para etiquetar")

    W, H, COLS, ROWS, MX, MY = 60, 36, 3, 7, 15, 20
    pdf = FPDF(unit="mm", format="A4")
    pdf.set_auto_page_break(False)
    for i, a in enumerate(assets):
        pos = i % (COLS * ROWS)
        if pos == 0:
            pdf.add_page()
        x, y = MX + (pos % COLS) * W, MY + (pos // COLS) * H
        pdf.rect(x, y, W, H)
        pdf.image(_qr_png(a.asset_tag), x=x + 2, y=y + 4, w=28, h=28)
        pdf.set_xy(x + 31, y + 7)
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(W - 33, 6, _latin(a.asset_tag))
        pdf.set_xy(x + 31, y + 14)
        pdf.set_font("Helvetica", size=7)
        pdf.multi_cell(W - 33, 3.5, _latin(f"{a.category}\n{a.brand} {a.model}"))
    raw = pdf.output()
    pdf_bytes = raw.encode("latin-1") if isinstance(raw, str) else bytes(raw)
    return StreamingResponse(
        BytesIO(pdf_bytes), media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=etiquetas.pdf"},
    )


# ---- papelera
@router.get("/papelera", response_model=list[ItAssetRead])
def papelera(session: Session = Depends(get_session)):
    return list(session.exec(
        select(ItAsset).where(ItAsset.deleted_at.is_not(None)).order_by(ItAsset.deleted_at.desc())
    ).all())


# ---- búsqueda / listado / alta
@router.get("/buscar", response_model=list[ItAssetRead])
def buscar(q: str, session: Session = Depends(get_session)):
    p = f"%{q}%"
    stmt = select(ItAsset).where(
        ItAsset.deleted_at.is_(None),
        ItAsset.asset_tag.ilike(p) | ItAsset.category.ilike(p) | ItAsset.brand.ilike(p)
        | ItAsset.model.ilike(p) | ItAsset.serial_number.ilike(p)
        | ItAsset.location.ilike(p) | ItAsset.assigned_to.ilike(p),
    )
    return list(session.exec(stmt.order_by(ItAsset.created_at.desc())).all())


@router.get("/", response_model=list[ItAssetRead])
def listar(
    status: str | None = None,
    category_id: int | None = None,
    limit: int = Query(2000, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    session: Session = Depends(get_session),
):
    stmt = select(ItAsset).where(ItAsset.deleted_at.is_(None))
    if status:
        stmt = stmt.where(ItAsset.status == status)
    if category_id is not None:
        stmt = stmt.where(ItAsset.category_id == category_id)
    return list(session.exec(stmt.order_by(ItAsset.created_at.desc()).offset(offset).limit(limit)).all())


@router.post("/", response_model=ItAssetRead, status_code=201)
def crear(payload: ItAssetCreate, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = ItAsset(**payload.model_dump())
    if asset.quantity is None:
        asset.quantity = 1
    if asset.category_id is not None:
        cat = session.get(Category, asset.category_id)
        if not cat:
            raise HTTPException(404, detail="Categoría no encontrada")
        asset.category = cat.name
    if asset.location_id is not None:
        asset.location = _resolve_location(session, asset.location_id)
    _validate_sn(session, asset)
    session.add(asset)
    try:
        session.commit()
    except IntegrityError as e:
        session.rollback()
        if "asset_tag" in str(e.orig).lower():
            raise HTTPException(409, detail="El Asset Tag ya existe. Por favor, cambia el Tag o selecciona otra categoría.")
        raise HTTPException(409, detail="Error de integridad en la base de datos. Revisa los datos.")
    session.refresh(asset)
    session.add(ItAssetHistory(
        asset_id=asset.id, field_name="registro", changed_by=user,
        new_value="Borrador creado" if asset.is_draft else "Activo creado",
    ))
    session.commit()
    session.refresh(asset)
    return asset


# ==============================================================================
# RUTAS DINÁMICAS (DEBEN IR AL FINAL)
# ==============================================================================
@router.get("/{asset_tag}", response_model=ItAssetRead)
def obtener(asset_tag: str, session: Session = Depends(get_session)):
    return _get_or_404(session, asset_tag)


@router.patch("/{asset_tag}", response_model=ItAssetRead)
def actualizar(asset_tag: str, payload: ItAssetUpdate, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = _get_or_404(session, asset_tag)
    data = payload.model_dump(exclude_unset=True)

    if data.get("category_id") is not None:
        cat = session.get(Category, data["category_id"])
        if not cat:
            raise HTTPException(404, detail="Categoría no encontrada")
        data["category"] = cat.name
    if "location_id" in data:
        data["location"] = _resolve_location(session, data["location_id"])

    was_draft = asset.is_draft
    for k, v in data.items():
        if v is None and k in NOT_NULL_FIELDS:
            continue
        if not was_draft:
            _log_change(session, asset.id, k, getattr(asset, k), v, user)
        setattr(asset, k, v)
    if was_draft and data.get("is_draft") is False:
        session.add(ItAssetHistory(asset_id=asset.id, field_name="registro", new_value="Registro finalizado", changed_by=user))

    with session.no_autoflush:
        _validate_sn(session, asset)
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, detail="El nuevo Tag ya existe en otro activo")
    session.refresh(asset)
    return asset


@router.get("/{asset_tag}/history", response_model=list[ItAssetHistoryRead])
def historial(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag, include_deleted=True)
    return list(session.exec(
        select(ItAssetHistory).where(ItAssetHistory.asset_id == asset.id).order_by(ItAssetHistory.changed_at.desc())
    ).all())


# ---- papelera (soft delete)
@router.delete("/{asset_tag}", status_code=204)
def eliminar(asset_tag: str, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = _get_or_404(session, asset_tag)
    asset.deleted_at = datetime.now(timezone.utc)
    session.add(ItAssetHistory(asset_id=asset.id, field_name="registro", new_value="Enviado a la papelera", changed_by=user))
    session.add(asset)
    session.commit()


@router.post("/{asset_tag}/restore", response_model=ItAssetRead)
def restaurar(asset_tag: str, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = _get_or_404(session, asset_tag, include_deleted=True)
    if asset.deleted_at is None:
        raise HTTPException(400, detail="El activo no está en la papelera")
    asset.deleted_at = None
    session.add(ItAssetHistory(asset_id=asset.id, field_name="registro", new_value="Restaurado de la papelera", changed_by=user))
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


@router.delete("/{asset_tag}/purge", status_code=204)
def purgar(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag, include_deleted=True)
    if asset.deleted_at is None:
        raise HTTPException(400, detail="Primero envíalo a la papelera")
    for img in asset.images:
        p = UPLOADS_DIR / img.filename
        if p.exists():
            p.unlink()
    for h in session.exec(select(ItAssetHistory).where(ItAssetHistory.asset_id == asset.id)).all():
        session.delete(h)
    for a in session.exec(select(ItAssetAssignment).where(ItAssetAssignment.asset_id == asset.id)).all():
        session.delete(a)
    session.delete(asset)
    session.commit()


# ---- asignaciones / custodia
@router.get("/{asset_tag}/assignments", response_model=list[AssignmentRead])
def asignaciones(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag, include_deleted=True)
    return list(session.exec(
        select(ItAssetAssignment).where(ItAssetAssignment.asset_id == asset.id).order_by(ItAssetAssignment.assigned_at.desc())
    ).all())


def _cerrar_abiertas(session: Session, asset_id: int, ahora: datetime, return_notes: str | None = None) -> None:
    for a in session.exec(select(ItAssetAssignment).where(
        ItAssetAssignment.asset_id == asset_id, ItAssetAssignment.returned_at.is_(None)
    )).all():
        a.returned_at = ahora
        a.return_notes = return_notes
        session.add(a)


@router.post("/{asset_tag}/assign", response_model=ItAssetRead)
def asignar(asset_tag: str, payload: AssignRequest, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = _get_or_404(session, asset_tag)
    emp = session.get(Employee, payload.employee_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    if not emp.active:
        raise HTTPException(400, detail="El empleado está inactivo")
    if asset.employee_id == emp.id:
        raise HTTPException(400, detail=f"El activo ya está asignado a {emp.name}")
    ahora = datetime.now(timezone.utc)
    _cerrar_abiertas(session, asset.id, ahora, "Reasignado")
    session.add(ItAssetAssignment(
        asset_id=asset.id, employee_id=emp.id, employee_name=emp.name,
        assigned_at=ahora, delivered_by=user, notes=(payload.notes or "").strip() or None,
    ))
    _log_change(session, asset.id, "asignado_a", asset.assigned_to, emp.name, user)
    asset.employee_id = emp.id
    asset.assigned_to = emp.name
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


@router.post("/{asset_tag}/return", response_model=ItAssetRead)
def devolver(asset_tag: str, payload: ReturnRequest, session: Session = Depends(get_session), user: str = Depends(current_user)):
    asset = _get_or_404(session, asset_tag)
    if not asset.employee_id and not asset.assigned_to:
        raise HTTPException(400, detail="El activo no está asignado")
    _cerrar_abiertas(session, asset.id, datetime.now(timezone.utc), (payload.notes or "").strip() or None)
    _log_change(session, asset.id, "asignado_a", asset.assigned_to, None, user)
    asset.employee_id = None
    asset.assigned_to = None
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


# ---- imágenes
@router.post("/{asset_tag}/images", response_model=list[ItAssetImageRead], status_code=201)
async def subir_imagenes(asset_tag: str, files: list[UploadFile] = File(...), session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    validados: list[tuple[bytes, str]] = []
    for f in files:
        if f.content_type not in ALLOWED_TYPES:
            raise HTTPException(415, detail=f"Tipo no permitido: {f.content_type}. Usa JPG, PNG o WEBP.")
        content = await f.read()
        if len(content) > MAX_SIZE_BYTES:
            raise HTTPException(413, detail=f"'{f.filename}' supera {MAX_SIZE_BYTES // (1024 * 1024)} MB")
        validados.append((content, EXT_MAP[f.content_type]))
    nuevas = []
    for content, ext in validados:
        filename = f"{uuid.uuid4().hex}.{ext}"
        (UPLOADS_DIR / filename).write_bytes(content)
        img = ItAssetImage(asset_id=asset.id, filename=filename)
        session.add(img)
        nuevas.append(img)
    session.commit()
    for img in nuevas:
        session.refresh(img)
    return nuevas


@router.delete("/{asset_tag}/images/{image_id}", status_code=204)
def eliminar_imagen(asset_tag: str, image_id: int, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    img = session.get(ItAssetImage, image_id)
    if img and img.asset_id == asset.id:
        p = UPLOADS_DIR / img.filename
        if p.exists():
            p.unlink()
        session.delete(img)
        session.commit()


# ---- QR individual y acta
@router.get("/{asset_tag}/qr")
def qr_png(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    return StreamingResponse(_qr_png(asset.asset_tag), media_type="image/png")


@router.get("/{asset_tag}/pdf")
def generar_pdf(asset_tag: str, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", size=16, style="B")
    pdf.cell(190, 10, txt=_latin("Acta de Recepción de Equipo TI"), ln=True, align="C")
    pdf.set_font("Helvetica", size=10)
    pdf.cell(190, 8, txt=_latin(f"Fecha: {datetime.now():%d/%m/%Y %H:%M}"), ln=True, align="C")
    pdf.set_font("Helvetica", size=12)
    pdf.ln(8)
    filas = [
        ("Tag", asset.asset_tag),
        ("Equipo", f"{asset.category} {asset.brand} {asset.model}"),
        ("Serial", asset.serial_number or "N/A"),
        ("Cantidad", f"{asset.quantity} {asset.unit}"),
        ("Estado", asset.status or "-"),
        ("Ubicación", asset.location or "-"),
        ("Asignado a", asset.assigned_to or "No asignado"),
    ]
    for k, v in filas:
        pdf.cell(190, 10, txt=_latin(f"{k}: {v}"), ln=True)
    for k, v in (asset.specs or {}).items():
        pdf.cell(190, 8, txt=_latin(f"  {k}: {v}"), ln=True)
    pdf.ln(30)
    pdf.cell(95, 10, txt="_________________________", ln=False)
    pdf.cell(95, 10, txt="_________________________", ln=True)
    pdf.cell(95, 10, txt="Firma Responsable TI", ln=False)
    pdf.cell(95, 10, txt="Firma de Recibido", ln=True)
    raw = pdf.output(dest="S")
    pdf_bytes = raw.encode("latin-1") if isinstance(raw, str) else bytes(raw)
    return StreamingResponse(
        BytesIO(pdf_bytes), media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=acta_{asset.asset_tag}.pdf"},
    )
