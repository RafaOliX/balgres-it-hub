"""Schemas Pydantic del módulo inventario."""
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

class ItAssetImageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    filename: str

class ItAssetHistoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    field_name: str
    old_value: Optional[str]
    new_value: Optional[str]
    changed_by: str
    changed_at: datetime

class ItAssetCreate(BaseModel):
    asset_tag: str = Field(min_length=1, max_length=64)
    category: str = Field(min_length=1, max_length=64)
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: str = Field(min_length=1, max_length=128)
    location: Optional[str] = None
    status: Optional[str] = "Operativo"
    notes: Optional[str] = None
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"

class ItAssetUpdate(BaseModel):
    asset_tag: Optional[str] = Field(default=None, min_length=1, max_length=64)
    category: Optional[str] = Field(default=None, min_length=1, max_length=64)
    brand: Optional[str] = Field(default=None, max_length=64)
    model: Optional[str] = Field(default=None, max_length=128)
    serial_number: Optional[str] = Field(default=None, min_length=1, max_length=128)
    location: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default=None, max_length=32)
    notes: Optional[str] = None
    quantity: Optional[int] = None
    unit: Optional[str] = None

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
    images: List[ItAssetImageRead] = []
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"
