"""Modelos de planos. Tablas nuevas: planos y plano_pins (sin FKs a otros módulos)."""
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Plano(SQLModel, table=True):
    __tablename__ = "planos"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(max_length=200, index=True)
    notes: Optional[str] = Field(default=None)
    filename: str = Field(max_length=256)  # dentro de UPLOADS_DIR/planos
    width: int = Field(default=0)
    height: int = Field(default=0)
    created_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)
    updated_at: datetime = Field(default_factory=_now, index=True)


class PlanoPin(SQLModel, table=True):
    __tablename__ = "plano_pins"
    id: Optional[int] = Field(default=None, primary_key=True)
    plano_id: int = Field(foreign_key="planos.id", index=True)
    x: float = Field(default=50.0)  # porcentaje del ancho (0-100)
    y: float = Field(default=50.0)  # porcentaje del alto (0-100)
    kind: str = Field(default="camara", max_length=32)
    label: Optional[str] = Field(default=None, max_length=128)
    asset_tag: Optional[str] = Field(default=None, max_length=64, index=True)  # solo el texto, sin FK
    notes: Optional[str] = Field(default=None)
