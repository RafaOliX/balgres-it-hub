"""Router FastAPI del módulo inventario."""
import os
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .db import apply_migrations, engine, get_session
from .models import ItAsset
from .schemas import ItAssetCreate, ItAssetRead, ItAssetUpdate

router = APIRouter(prefix="/inventario", tags=["inventario"])

UPLOADS_DIR = Path(os.getenv("UPLOADS_DIR", "/app/uploads"))
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB


def init_db() -> None:
    """Crea tablas y aplica migraciones. Se invoca al arrancar core-api."""
    SQLModel.metadata.create_all(engine)
    apply_migrations()


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}


@router.get("/", response_model=list[ItAssetRead])
def listar(session: Session = Depends(get_session)) -> list[ItAsset]:
    return session.exec(select(ItAsset)).all()


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
    return session.exec(stmt).all()


@router.post("/", response_model=ItAssetRead, status_code=status.HTTP_201_CREATED)
def crear(payload: ItAssetCreate, session: Session = Depends(get_session)) -> ItAsset:
    asset = ItAsset(**payload.model_dump())
    session.add(asset)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="asset_tag o serial_number ya existen",
        ) from None
    session.refresh(asset)
    return asset


@router.get("/{asset_tag}", response_model=ItAssetRead)
def obtener(asset_tag: str, session: Session = Depends(get_session)) -> ItAsset:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == asset_tag)).first()
    if asset is None:
        raise HTTPException(status_code=404, detail=f"No existe activo con tag '{asset_tag}'")
    return asset


@router.patch("/{asset_tag}", response_model=ItAssetRead)
def actualizar(
    asset_tag: str,
    payload: ItAssetUpdate,
    session: Session = Depends(get_session),
) -> ItAsset:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == asset_tag)).first()
    if asset is None:
        raise HTTPException(status_code=404, detail=f"No existe activo con tag '{asset_tag}'")

    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(asset, k, v)
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


@router.delete("/{asset_tag}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar(asset_tag: str, session: Session = Depends(get_session)) -> None:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == asset_tag)).first()
    if asset is None:
        raise HTTPException(status_code=404, detail=f"No existe activo con tag '{asset_tag}'")
    # Borrar imagen asociada si existe
    if asset.image_path:
        old = UPLOADS_DIR / asset.image_path
        if old.exists():
            old.unlink()
    session.delete(asset)
    session.commit()


# ──────────────── Imágenes ────────────────

@router.post("/{asset_tag}/image", response_model=ItAssetRead)
async def subir_imagen(
    asset_tag: str,
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
) -> ItAsset:
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo no permitido: {file.content_type}. Solo JPEG, PNG, WebP.",
        )

    content = await file.read()
    if len(content) > MAX_SIZE_BYTES:
        raise HTTPException(status_code=400, detail="Archivo mayor a 5 MB")
    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Archivo vacío")

    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == asset_tag)).first()
    if asset is None:
        raise HTTPException(status_code=404, detail=f"No existe activo con tag '{asset_tag}'")

    ext_map = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
    ext = ext_map[file.content_type]
    filename = f"{uuid.uuid4().hex}.{ext}"

    (UPLOADS_DIR / filename).write_bytes(content)

    if asset.image_path:
        old = UPLOADS_DIR / asset.image_path
        if old.exists():
            old.unlink()

    asset.image_path = filename
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


@router.delete("/{asset_tag}/image", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_imagen(asset_tag: str, session: Session = Depends(get_session)) -> None:
    asset = session.exec(select(ItAsset).where(ItAsset.asset_tag == asset_tag)).first()
    if asset is None:
        raise HTTPException(status_code=404, detail=f"No existe activo con tag '{asset_tag}'")
    if asset.image_path:
        old = UPLOADS_DIR / asset.image_path
        if old.exists():
            old.unlink()
        asset.image_path = None
        session.add(asset)
        session.commit()
