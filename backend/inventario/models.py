"""Modelos SQLModel del módulo inventario."""
from datetime import date, datetime, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, Relationship, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Category(SQLModel, table=True):
    __tablename__ = "categories"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True, index=True, max_length=64)
    parent_id: Optional[int] = Field(default=None, foreign_key="categories.id")
    prefix: str = Field(max_length=10)
    unit: str = Field(default="Unidad", max_length=32)
    requires_sn: bool = Field(default=True)
    # Campos técnicos que se piden al registrar un activo de esta categoría
    spec_fields: Optional[List[str]] = Field(default=None, sa_column=Column(JSON))


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
    active: bool = Field(default=True)


class ItAssetImage(SQLModel, table=True):
    __tablename__ = "it_asset_images"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", ondelete="CASCADE", index=True)
    filename: str = Field(max_length=256, index=True)
    created_at: datetime = Field(default_factory=_now)
    asset: Optional["ItAsset"] = Relationship(back_populates="images")


class ItAssetHistory(SQLModel, table=True):
    __tablename__ = "it_asset_history"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", ondelete="CASCADE", index=True)
    field_name: str = Field(max_length=64)
    old_value: Optional[str] = Field(default=None)
    new_value: Optional[str] = Field(default=None)
    changed_by: str = Field(max_length=64, default="admin")
    changed_at: datetime = Field(default_factory=_now)


class ItAssetAssignment(SQLModel, table=True):
    """Custodia: quién tuvo el activo y cuándo."""
    __tablename__ = "it_asset_assignments"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_id: int = Field(foreign_key="it_assets.id", ondelete="CASCADE", index=True)
    employee_id: Optional[int] = Field(default=None, foreign_key="employees.id")
    employee_name: str = Field(max_length=128)  # copia por si el empleado cambia de nombre
    assigned_at: datetime = Field(default_factory=_now)
    returned_at: Optional[datetime] = Field(default=None)
    delivered_by: str = Field(default="admin", max_length=64)
    notes: Optional[str] = Field(default=None)
    return_notes: Optional[str] = Field(default=None)


class ItAsset(SQLModel, table=True):
    __tablename__ = "it_assets"
    id: Optional[int] = Field(default=None, primary_key=True)
    asset_tag: str = Field(unique=True, index=True, max_length=64)
    category: str = Field(index=True, max_length=64)
    category_id: Optional[int] = Field(default=None, foreign_key="categories.id")

    brand: str = Field(max_length=64)
    model: str = Field(max_length=128)
    serial_number: Optional[str] = Field(default=None, index=True, max_length=128)

    location: Optional[str] = Field(default=None, max_length=256)  # texto derivado de location_id (o legado)
    location_id: Optional[int] = Field(default=None, foreign_key="locations.id")
    status: Optional[str] = Field(default="Operativo", max_length=32)
    notes: Optional[str] = Field(default=None)
    quantity: int = Field(default=1)
    unit: Optional[str] = Field(default="Unidad", max_length=32)
    assigned_to: Optional[str] = Field(default=None, max_length=128)  # nombre del custodio actual
    employee_id: Optional[int] = Field(default=None, foreign_key="employees.id")

    # Compra y garantía
    purchase_date: Optional[date] = Field(default=None)
    cost: Optional[float] = Field(default=None)
    supplier: Optional[str] = Field(default=None, max_length=128)
    invoice_number: Optional[str] = Field(default=None, max_length=64)
    warranty_until: Optional[date] = Field(default=None)

    # Campos técnicos libres por categoría (RAM, CPU, IP, MAC...)
    specs: Optional[Dict[str, Any]] = Field(default=None, sa_column=Column(JSON))

    created_at: datetime = Field(default_factory=_now)
    is_draft: bool = Field(default=False)
    deleted_at: Optional[datetime] = Field(default=None, index=True)  # soft delete

    images: List[ItAssetImage] = Relationship(
        back_populates="asset",
        sa_relationship_kwargs={"cascade": "all, delete-orphan", "lazy": "selectin", "order_by": "ItAssetImage.id"},
    )
