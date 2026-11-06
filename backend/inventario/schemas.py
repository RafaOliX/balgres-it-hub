"""Schemas Pydantic del módulo inventario."""
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator

class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    parent_id: Optional[int] = None
    prefix: str = Field(min_length=1, max_length=10)
    unit: str = "Unidad"
    requires_sn: bool = True

class CategoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    parent_id: Optional[int]
    prefix: str
    unit: str
    requires_sn: bool

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
    category_id: Optional[int] = None
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: Optional[str] = None
    location: Optional[str] = None
    status: Optional[str] = "Operativo"
    notes: Optional[str] = None
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"
    assigned_to: Optional[str] = None

    @field_validator('serial_number', 'location', 'notes', 'assigned_to')
    @classmethod
    def empty_to_none(cls, v: str | None) -> str | None:
        if v is not None and v.strip() == "":
            return None
        return v

class ItAssetUpdate(BaseModel):
    asset_tag: Optional[str] = Field(default=None, min_length=1, max_length=64)
    category: Optional[str] = Field(default=None, min_length=1, max_length=64)
    category_id: Optional[int] = None
    brand: Optional[str] = Field(default=None, max_length=64)
    model: Optional[str] = Field(default=None, max_length=128)
    serial_number: Optional[str] = None
    location: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default=None, max_length=32)
    notes: Optional[str] = None
    quantity: Optional[int] = None
    unit: Optional[str] = None
    assigned_to: Optional[str] = None

    @field_validator('serial_number', 'location', 'notes', 'assigned_to')
    @classmethod
    def empty_to_none(cls, v: str | None) -> str | None:
        if v is not None and v.strip() == "":
            return None
        return v

class ItAssetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    asset_tag: str
    category: str
    category_id: Optional[int]
    brand: str
    model: str
    serial_number: Optional[str]
    location: Optional[str]
    status: Optional[str]
    notes: Optional[str]
    images: List[ItAssetImageRead] = []
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"
    assigned_to: Optional[str] = None
