"""Schemas Pydantic del módulo inventario."""
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class ItAssetCreate(BaseModel):
    asset_tag: str = Field(min_length=1, max_length=64)
    category: str = Field(min_length=1, max_length=64)
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: str = Field(min_length=1, max_length=128)
    location: Optional[str] = None
    status: Optional[str] = "Operativo"
    notes: Optional[str] = None


class ItAssetUpdate(BaseModel):
    location: Optional[str] = None
    status: Optional[str] = None
    notes: Optional[str] = None


class ItAssetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    asset_tag: str
    category: str
    brand: str
    model: str
    serial_number: str
    location: Optional[str]
    status: Optional[str]
    notes: Optional[str]
    image_path: Optional[str]
