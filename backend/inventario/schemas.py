"""Schemas Pydantic del módulo inventario."""
import re
from datetime import date, datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _blank_to_none(v):
    if isinstance(v, str) and v.strip() == "":
        return None
    return v


Status = Literal["Operativo", "En Revisión", "Retirado"]


# ---------------------------------------------------------------- categorías
class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    parent_id: Optional[int] = None
    prefix: str = Field(min_length=1, max_length=10)
    unit: str = "Unidad"
    requires_sn: bool = True
    spec_fields: Optional[List[str]] = None

    @field_validator("spec_fields")
    @classmethod
    def clean_specs(cls, v):
        if v is None:
            return None
        out: list[str] = []
        for s in v:
            s = " ".join(str(s).split())
            if s and s not in out:
                out.append(s)
        return out


class CategoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    parent_id: Optional[int]
    prefix: str
    unit: str
    requires_sn: bool
    spec_fields: Optional[List[str]] = None


# ---------------------------------------------------------------- ubicaciones / empleados
class LocationCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    parent_id: Optional[int] = None
    kind: Optional[str] = Field(default=None, max_length=32)

    @field_validator("kind")
    @classmethod
    def _k(cls, v):
        return _blank_to_none(v)


class LocationRead(BaseModel):
    id: int
    name: str
    parent_id: Optional[int]
    kind: Optional[str]
    full_name: str


class EmployeeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    email: Optional[str] = Field(default=None, max_length=128)
    department: Optional[str] = Field(default=None, max_length=128)
    employee_code: Optional[str] = Field(default=None, max_length=64)
    position: Optional[str] = Field(default=None, max_length=128)
    phone: Optional[str] = Field(default=None, max_length=40)
    extension: Optional[str] = Field(default=None, max_length=20)
    location_id: Optional[int] = None
    notes: Optional[str] = None
    active: bool = True

    @field_validator("email", "department", "employee_code", "position", "phone", "extension", "notes")
    @classmethod
    def _e(cls, v):
        return _blank_to_none(v)

    @field_validator("phone", "extension")
    @classmethod
    def _fmt(cls, v, info):
        if v is None:
            return v
        v = v.strip()
        if info.field_name == "extension":
            if not re.fullmatch(r"\d{1,10}", v):
                raise ValueError("La extensión debe ser numérica (máx. 10 dígitos)")
        elif not re.fullmatch(r"[\d+()\-\s.]{5,25}", v):
            raise ValueError("Teléfono inválido: usa números, +, -, paréntesis")
        return v


class EmployeeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    email: Optional[str]
    department: Optional[str]
    employee_code: Optional[str] = None
    position: Optional[str] = None
    phone: Optional[str] = None
    extension: Optional[str] = None
    location_id: Optional[int] = None
    notes: Optional[str] = None
    active: bool


# ---------------------------------------------------------------- asignaciones
class AssignRequest(BaseModel):
    employee_id: int
    notes: Optional[str] = None


class ReturnRequest(BaseModel):
    notes: Optional[str] = None


class AssignmentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: Optional[int]
    employee_name: str
    assigned_at: datetime
    returned_at: Optional[datetime]
    delivered_by: str
    notes: Optional[str]
    return_notes: Optional[str]


# ---------------------------------------------------------------- activos
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


_OPT_TEXT = ("serial_number", "location", "notes")


class ItAssetCreate(BaseModel):
    asset_tag: str = Field(min_length=1, max_length=64)
    category: str = Field(min_length=1, max_length=64)
    category_id: Optional[int] = None
    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: Optional[str] = None
    location: Optional[str] = None
    location_id: Optional[int] = None
    status: Optional[Status] = "Operativo"
    notes: Optional[str] = None
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"
    is_draft: Optional[bool] = False
    specs: Optional[Dict[str, Any]] = None

    @field_validator(*_OPT_TEXT, check_fields=False)
    @classmethod
    def empty_to_none(cls, v):
        return _blank_to_none(v)


class ItAssetUpdate(BaseModel):
    category: Optional[str] = Field(default=None, min_length=1, max_length=64)
    category_id: Optional[int] = None
    brand: Optional[str] = Field(default=None, max_length=64)
    model: Optional[str] = Field(default=None, max_length=128)
    serial_number: Optional[str] = None
    location_id: Optional[int] = None
    status: Optional[Status] = None
    notes: Optional[str] = None
    quantity: Optional[int] = None
    unit: Optional[str] = None
    is_draft: Optional[bool] = None
    specs: Optional[Dict[str, Any]] = None

    @field_validator(*_OPT_TEXT, check_fields=False)
    @classmethod
    def empty_to_none(cls, v):
        return _blank_to_none(v)


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
    location_id: Optional[int] = None
    status: Optional[str]
    notes: Optional[str]
    images: List[ItAssetImageRead] = []
    quantity: Optional[int] = 1
    unit: Optional[str] = "Unidad"
    assigned_to: Optional[str] = None
    employee_id: Optional[int] = None
    specs: Optional[Dict[str, Any]] = None
    created_at: datetime
    is_draft: bool
    deleted_at: Optional[datetime] = None
