"""Modelos SQLModel del módulo inventario."""
from datetime import datetime
from typing import List, Optional

from sqlmodel import Field, Relationship, SQLModel


class ItAssetImage(SQLModel, table=True):
    __tablename__ = "it_asset_images"

    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", index=True)
    filename: str = Field(max_length=256, index=True)
    created_at: Optional[datetime] = Field(default_factory=datetime.utcnow)

    asset: Optional["ItAsset"] = Relationship(back_populates="images")


class ItAsset(SQLModel, table=True):
    __tablename__ = "it_assets"

    id: Optional[int] = Field(default=None, primary_key=True)
    asset_tag: str = Field(unique=True, index=True, max_length=64)
    category: str = Field(index=True, max_length=64)
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: str = Field(unique=True, index=True, max_length=128)
    location: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default="Operativo", max_length=32)
    notes: Optional[str] = Field(default=None)

    images: List[ItAssetImage] = Relationship(
        back_populates="asset",
        sa_relationship_kwargs={
            "cascade": "all, delete-orphan",
            "lazy": "selectin",
            "order_by": "ItAssetImage.id",
        },
    )
