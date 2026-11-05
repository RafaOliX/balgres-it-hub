"""Router FastAPI del módulo inventario."""
import os
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .db import apply_migrations, engine, get_session
from .models import ItAsset, ItAssetImage
from .schemas import ItAssetCreate, ItAssetImageRead, ItAssetRead, ItAssetUpdate

router = APIRouter(prefix="/inventario", tags=["inventario"])

UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB por archivo
MAX_IMAGES_PER_ASSET = 20
EXT_MAP = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def init_db() -> None:
    """Crea tablas y aplica migraciones. Se invoca al arrancar core-api."""
    SQLModel.metadata.create_all(engine)
    apply_migrations()


def _get_or_404(session: Session, tag: str) -> ItAsset:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == tag)).first()
    if asset is None:
        raise HTTPException(404, detail=f"No existe activo con tag '{tag}'")
    return asset


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}


@router.get("/", response_model=list[ItAssetRead])
def listar(session: Session = Depends(get_session)) -> list[ItAsset]:
    return list(session.exec(select(ItAsset)).all())


@router.get("/buscar", response_model=list[ItAssetRead])
def buscar(
    q: str = Query(..., min_length=1, description="Tag, categoría, marca, modelo, S/N o ubicación"),
    session: Session = Depends(get_session),
) -> list[ItAsset]:
    pattern = f"%{q}%"
    stmt = select(ItAsset).where(
        ItAsset.asset_tag.ilike(pattern)
        | ItAsset.category.ilike(pattern)
        | ItAsset.brand.ilike(pattern)
        | ItAsset.model.ilike(pattern)
        | ItAsset.serial_number.ilike(pattern)
        | ItAsset.location.ilike(pattern)
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
    return asset


@router.get("/{asset_tag}", response_model=ItAssetRead)
def obtener(asset_tag: str, session: Session = Depends(get_session)) -> ItAsset:
    return _get_or_404(session, asset_tag)


@router.patch("/{asset_tag}", response_model=ItAssetRead)
def actualizar(
    asset_tag: str,
    payload: ItAssetUpdate,
    session: Session = Depends(get_session),
) -> ItAsset:
    asset = _get_or_404(session, asset_tag)
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(asset, k, v)
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


@router.delete("/{asset_tag}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar(asset_tag: str, session: Session = Depends(get_session)) -> None:
    asset = _get_or_404(session, asset_tag)
    # Borrar archivos físicos (el cascade de la relación borra las filas)
    for img in asset.images:
        p = UPLOADS_DIR / img.filename
        if p.exists():
            p.unlink()
    session.delete(asset)
    session.commit()


# ──────────────── Imágenes (1:N) ────────────────

@router.get("/{asset_tag}/images", response_model=list[ItAssetImageRead])
def listar_imagenes(asset_tag: str, session: Session = Depends(get_session)) -> list[ItAssetImage]:
    asset = _get_or_404(session, asset_tag)
    return list(asset.images)


@router.post("/{asset_tag}/images", response_model=list[ItAssetImageRead], status_code=status.HTTP_201_CREATED)
async def subir_imagenes(
    asset_tag: str,
    files: list[UploadFile] = File(...),
    session: Session = Depends(get_session),
) -> list[ItAssetImage]:
    asset = _get_or_404(session, asset_tag)

    if len(asset.images) + len(files) > MAX_IMAGES_PER_ASSET:
        raise HTTPException(
            400,
            detail=f"Máximo {MAX_IMAGES_PER_ASSET} imágenes por activo "
                   f"(actuales: {len(asset.images)}, nuevas: {len(files)})",
        )

    nuevas: list[ItAssetImage] = []
    for f in files:
        if f.content_type not in ALLOWED_TYPES:
            raise HTTPException(400, detail=f"Tipo no permitido: {f.content_type}")
        content = await f.read()
        if not content:
            raise HTTPException(400, detail=f"Archivo vacío: {f.filename}")
        if len(content) > MAX_SIZE_BYTES:
            raise HTTPException(400, detail=f"Archivo mayor a 5 MB: {f.filename}")

        filename = f"{uuid.uuid4().hex}.{EXT_MAP[f.content_type]}"
        (UPLOADS_DIR / filename).write_bytes(content)
        img = ItAssetImage(asset_id=asset.id, filename=filename)
        session.add(img)
        nuevas.append(img)

    session.commit()
    for img in nuevas:
        session.refresh(img)
    return nuevas


@router.delete("/{asset_tag}/images/{image_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_imagen(
    asset_tag: str,
    image_id: int,
    session: Session = Depends(get_session),
) -> None:
    asset = _get_or_404(session, asset_tag)
    img = session.get(ItAssetImage, image_id)
    if img is None or img.asset_id != asset.id:
        raise HTTPException(404, detail="Imagen no encontrada")
    p = UPLOADS_DIR / img.filename
    if p.exists():
        p.unlink()
    session.delete(img)
    session.commit()
