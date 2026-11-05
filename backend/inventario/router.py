"""Router FastAPI del módulo inventario."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from .db import engine, get_session
from .models import ItAsset
from .schemas import ItAssetCreate, ItAssetRead, ItAssetUpdate

router = APIRouter(prefix="/inventario", tags=["inventario"])


def init_db() -> None:
    """Crea las tablas del módulo. Se invoca al arrancar core-api."""
    SQLModel.metadata.create_all(engine)


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
    session.delete(asset)
    session.commit()
