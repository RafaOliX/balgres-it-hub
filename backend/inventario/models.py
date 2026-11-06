"""Modelos SQLModel del módulo inventario."""
from datetime import datetime, timezone
from typing import List, Optional
from sqlmodel import Field, Relationship, SQLModel

class Category(SQLModel, table=True):
    __tablename__ = "categories"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True, index=True, max_length=64)
    parent_id: Optional[int] = Field(default=None, foreign_key="categories.id")
    prefix: str = Field(max_length=10)
    unit: str = Field(default="Unidad", max_length=32)
    requires_sn: bool = Field(default=True)
    subcategories: List["Category"] = Relationship()

class ItAssetImage(SQLModel, table=True):
    __tablename__ = "it_asset_images"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", ondelete="CASCADE", index=True)
    filename: str = Field(max_length=256, index=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    asset: Optional["ItAsset"] = Relationship(back_populates="images")

class ItAssetHistory(SQLModel, table=True):
    __tablename__ = "it_asset_history"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", ondelete="CASCADE", index=True)
    field_name: str = Field(max_length=64)
    old_value: Optional[str] = Field(default=None)
    new_value: Optional[str] = Field(default=None)
    changed_by: str = Field(max_length=64, default="admin")
    changed_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class ItAsset(SQLModel, table=True):
    __tablename__ = "it_assets"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_tag: str = Field(unique=True, index=True, max_length=64)
    category: str = Field(index=True, max_length=64)
    category_id: Optional[int] = Field(default=None, foreign_key="categories.id")
    
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    # Serial ya NO es único, para permitir duplicados
    serial_number: Optional[str] = Field(default=None, index=True, max_length=128)
    
    location: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default="Operativo", max_length=32)
    notes: Optional[str] = Field(default=None)
    quantity: int = Field(default=1)
    unit: Optional[str] = Field(default="Unidad", max_length=32)
    assigned_to: Optional[str] = Field(default=None, max_length=128)
    
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    is_draft: bool = Field(default=False)

    images: List[ItAssetImage] = Relationship(
        back_populates="asset",
        sa_relationship_kwargs={"cascade": "all, delete-orphan", "lazy": "selectin", "order_by": "ItAssetImage.id"},
    )
