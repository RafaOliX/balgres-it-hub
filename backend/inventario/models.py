"""Modelos SQLModel del módulo inventario."""
from typing import Optional

from sqlmodel import Field, SQLModel


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
