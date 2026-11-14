"""Modelos de contacts. Mismas tablas que antes (locations, employees)."""
from typing import Optional

from sqlmodel import Field, SQLModel


class Location(SQLModel, table=True):
    __tablename__ = "locations"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(max_length=128, index=True)
    parent_id: Optional[int] = Field(default=None, foreign_key="locations.id")
    kind: Optional[str] = Field(default=None, max_length=32)  # Sede / Área / Oficina / Bodega


class Employee(SQLModel, table=True):
    __tablename__ = "employees"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(max_length=128, index=True)
    email: Optional[str] = Field(default=None, max_length=128)
    department: Optional[str] = Field(default=None, max_length=128)
    employee_code: Optional[str] = Field(default=None, max_length=64)
    position: Optional[str] = Field(default=None, max_length=128)
    phone: Optional[str] = Field(default=None, max_length=40)
    extension: Optional[str] = Field(default=None, max_length=20)
    location_id: Optional[int] = Field(default=None, foreign_key="locations.id")
    notes: Optional[str] = Field(default=None)
    active: bool = Field(default=True)
