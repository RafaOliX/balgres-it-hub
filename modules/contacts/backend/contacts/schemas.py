"""Schemas Pydantic de contacts."""
import re
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _blank_to_none(v):
    if isinstance(v, str) and v.strip() == "":
        return None
    return v


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
