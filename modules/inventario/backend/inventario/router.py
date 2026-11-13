"""Router FastAPI del módulo inventario."""
import os
import re
import uuid
from datetime import date, datetime, timedelta, timezone
from io import BytesIO
from pathlib import Path

import pandas as pd
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from fpdf import FPDF
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .actas import DEFAULT_CONFIG, render_acta, seed_templates
from .actas import router as actas_router
from . import contacts_link  # noqa: F401
from .catalogos import router as catalogos_router
from .common import current_user, location_paths
from .db import apply_migrations, engine, get_session
from .models import ActaTemplate, Category, Employee, ItAsset, ItAssetAssignment, ItAssetHistory, ItAssetImage, Location
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
    seed_templates()


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

@router.post("/{asset_tag}/adjust-stock", response_model=ItAssetRead)
def ajustar_stock(asset_tag: str, amount: int, session: Session = Depends(get_session), user: str = Depends(current_user)):
    """Suma o resta cantidad al stock (ej. usar un cable)."""
    asset = _get_or_404(session, asset_tag)
    nueva_cantidad = asset.quantity + amount
    if nueva_cantidad < 0:
        raise HTTPException(400, detail="El stock no puede ser negativo")
    
    _log_change(session, asset.id, "quantity", asset.quantity, nueva_cantidad, user)
    asset.quantity = nueva_cantidad
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset

# ==============================================================================
# RUTAS FIJAS (DEBEN IR PRIMERO PARA EVITAR QUE /{asset_tag} LAS ATRAPE)
# ==============================================================================
@router.get("/version")
def version(session: Session = Depends(get_session)):
    """Huella barata del inventario: el cliente solo recarga la lista cuando cambia."""
    from sqlalchemy import func
    n = session.exec(select(func.count()).select_from(ItAsset)).one()
    last = session.exec(select(func.max(ItAsset.updated_at))).one()
    imgs = session.exec(select(func.count()).select_from(ItAssetImage)).one()
    return {"v": f"{n}-{last}-{imgs}"}


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}


# /locations, /employees, /dashboard
router.include_router(catalogos_router)
router.include_router(actas_router)


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
    "Asignado a", "Notas",
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


_STATUS_MAP = {"operativo": "Operativo", "en revision": "En Revisión", "en revisión": "En Revisión", "retirado": "Retirado"}


def _k(v) -> str:
    return " ".join(str(v).split()).lower()


@router.post("/import")
async def importar_excel(file: UploadFile = File(...), session: Session = Depends(get_session), user: str = Depends(current_user)):
    try:
        df = pd.read_excel(BytesIO(await file.read()), dtype=str)
    except Exception:
        raise HTTPException(400, detail="No se pudo leer el archivo. Debe ser un .xlsx válido.")
    faltan = {"Tag", "Categoría", "Marca", "Modelo"} - set(df.columns)
    if faltan:
        raise HTTPException(400, detail=f"Faltan columnas obligatorias: {', '.join(sorted(faltan))}")

    cats = {c.name.lower(): c for c in session.exec(select(Category)).all()}
    existentes = set(session.exec(select(ItAsset.asset_tag)).all())
    paths = location_paths(session)
    locs = {_k(p): lid for lid, p in paths.items()}
    for l in session.exec(select(Location).where(Location.parent_id.is_(None))).all():
        locs.setdefault(_k(l.name), l.id)
    emps = {_k(e.name): e for e in session.exec(select(Employee)).all()}
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
        st_raw = _clean(row.get("Estado"))
        status_val = _STATUS_MAP.get(_k(st_raw)) if st_raw else "Operativo"
        if status_val is None:
            errores.append({"fila": fila, "detalle": f"Estado inválido '{st_raw}' (Operativo, En Revisión, Retirado)"})
            continue
        sn = _clean(row.get("S/N"))
        if cat.requires_sn and not sn:
            errores.append({"fila": fila, "detalle": f"La categoría '{cat.name}' requiere S/N"})
            continue

        loc_id = None
        loc_txt = _clean(row.get("Ubicación"))
        if loc_txt:
            loc_id = locs.get(_k(loc_txt))
            if loc_id is None:
                loc = Location(name=" ".join(loc_txt.split()))
                session.add(loc)
                session.flush()
                loc_id = loc.id
                locs[_k(loc_txt)] = loc_id
                paths[loc_id] = loc.name
        emp = None
        who = _clean(row.get("Asignado a"))
        if who:
            emp = emps.get(_k(who))
            if emp is None:
                emp = Employee(name=" ".join(who.split()))
                session.add(emp)
                session.flush()
                emps[_k(who)] = emp

        asset = ItAsset(
            asset_tag=tag, category=cat.name, category_id=cat.id, brand=brand, model=model, serial_number=sn,
            quantity=qty, unit=_clean(row.get("Unidad")) or cat.unit,
            location=paths.get(loc_id) if loc_id else None, location_id=loc_id, status=status_val,
            notes=_clean(row.get("Notas")), employee_id=emp.id if emp else None, assigned_to=emp.name if emp else None,
        )
        session.add(asset)
        session.flush()
        session.add(ItAssetHistory(asset_id=asset.id, field_name="registro", new_value="Importado desde Excel", changed_by=user))
        if emp:
            session.add(ItAssetAssignment(asset_id=asset.id, employee_id=emp.id, employee_name=emp.name, delivered_by=user, notes="Importado desde Excel"))
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


# ---- limpieza de borradores
@router.delete("/borradores")
def limpiar_borradores(dias: int = Query(7, ge=0, le=365), session: Session = Depends(get_session)):
    """Elimina definitivamente los borradores sin finalizar con más de N días."""
    limite = datetime.now(timezone.utc) - timedelta(days=dias)
    borradores = session.exec(
        select(ItAsset).where(ItAsset.is_draft == True, ItAsset.created_at < limite)  # noqa: E712
    ).all()
    for a in borradores:
        for img in a.images:
            p = UPLOADS_DIR / img.filename
            if p.exists():
                p.unlink()
        for h in session.exec(select(ItAssetHistory).where(ItAssetHistory.asset_id == a.id)).all():
            session.delete(h)
        for x in session.exec(select(ItAssetAssignment).where(ItAssetAssignment.asset_id == a.id)).all():
            session.delete(x)
        session.delete(a)
    session.commit()
    return {"eliminados": len(borradores)}


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
def crear(payload: ItAssetCreate, auto_tag: bool = False, session: Session = Depends(get_session), user: str = Depends(current_user)):
    """Con auto_tag=true el servidor asigna el siguiente tag de la categoría y reintenta si hubo colisión."""
    if not (auto_tag and payload.category_id is not None):
        return _crear(payload, session, user)
    cat = session.get(Category, payload.category_id)
    if not cat:
        raise HTTPException(404, detail="Categoría no encontrada")
    last: HTTPException | None = None
    for _ in range(6):
        payload.asset_tag = _next_tag(session, cat.prefix)
        try:
            return _crear(payload, session, user)
        except HTTPException as e:
            if e.status_code != 409 or "Tag" not in str(e.detail):
                raise
            session.rollback()
            last = e
    raise last  # type: ignore[misc]


def _crear(payload: ItAssetCreate, session: Session, user: str):
    # Verificar si el Tag ya existe
    existente = session.exec(select(ItAsset).where(ItAsset.asset_tag == payload.asset_tag)).first()
    if existente:
        if existente.deleted_at is not None:
            raise HTTPException(409, detail=f"El Tag '{payload.asset_tag}' está en la Papelera. Restáuralo o usa otro Tag.")
        if existente.is_draft:
            # Upsert: Convertir borrador en activo final
            for k, v in payload.model_dump(exclude_unset=True).items():
                setattr(existente, k, v)
            existente.is_draft = False
            _validate_sn(session, existente)
            session.add(existente)
            session.commit()
            session.refresh(existente)
            return existente
        else:
            raise HTTPException(409, detail=f"El Tag '{payload.asset_tag}' ya está asignado a un activo final.")

    asset = ItAsset(**payload.model_dump())
    if asset.serial_number is not None and asset.serial_number.strip() == "":
        asset.serial_number = None
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
        error_msg = str(e.orig).lower()
        if "asset_tag" in error_msg:
            raise HTTPException(409, detail="El Asset Tag ya existe. Por favor, cambia el Tag o selecciona otra categoría.")
        elif "serial_number" in error_msg:
            raise HTTPException(409, detail="El Número de Serie (S/N) ya existe en otro equipo. Si no tiene S/N, déjalo en blanco.")
        else:
            raise HTTPException(409, detail=f"Error de integridad en la base de datos: {str(e.orig)}")
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
        if k == 'serial_number' and isinstance(v, str) and v.strip() == "":
            v = None
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
    except IntegrityError as e:
        session.rollback()
        error_msg = str(e.orig).lower()
        if "asset_tag" in error_msg:
            raise HTTPException(409, detail="El nuevo Tag ya existe en otro activo.")
        elif "serial_number" in error_msg:
            raise HTTPException(409, detail="El nuevo S/N ya existe en otro activo.")
        else:
            raise HTTPException(409, detail=f"Error de integridad: {str(e.orig)}")
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
    ahora = datetime.now(timezone.utc)
    asset.deleted_at = ahora
    if asset.employee_id or asset.assigned_to:  # cierra la custodia abierta
        _cerrar_abiertas(session, asset.id, ahora, "Enviado a la papelera")
        _log_change(session, asset.id, "asignado_a", asset.assigned_to, None, user)
        asset.employee_id = None
        asset.assigned_to = None
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
        try:
            from PIL import Image
            with Image.open(BytesIO(content)) as im:
                fmt = (im.format or "").upper()
                im.verify()
        except Exception:
            raise HTTPException(415, detail=f"'{f.filename}' no es una imagen válida.")
        ext = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}.get(fmt)
        if ext is None:
            raise HTTPException(415, detail=f"Formato no permitido en '{f.filename}'. Usa JPG, PNG o WEBP.")
        validados.append((content, ext))
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
def generar_pdf(asset_tag: str, template_id: int | None = None, session: Session = Depends(get_session)):
    asset = _get_or_404(session, asset_tag)
    cfg = DEFAULT_CONFIG
    if template_id is not None:
        t = session.get(ActaTemplate, template_id)
        if not t:
            raise HTTPException(404, detail="Plantilla no encontrada")
        cfg = t.config
    emp = session.get(Employee, asset.employee_id) if asset.employee_id else None
    data = render_acta(session, cfg, emp, [asset])
    return StreamingResponse(
        BytesIO(data), media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=acta_{asset.asset_tag}.pdf"},
    )
