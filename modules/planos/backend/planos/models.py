"""Modelos de planos. Tablas: planos, plano_pins y plano_trazos (sin FKs a otros módulos)."""
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import JSON, Column
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
    nota_id: Optional[int] = Field(default=None)  # nota de documentación (sin FK)
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
    nota_id: Optional[int] = Field(default=None)  # nota de documentación (sin FK)


class PlanoTrazo(SQLModel, table=True):
    """Dibujo sobre el plano: puntos en porcentaje (0-100); width relativo a un lienzo de 1000 px."""
    __tablename__ = "plano_trazos"
    id: Optional[int] = Field(default=None, primary_key=True)
    plano_id: int = Field(foreign_key="planos.id", index=True)
    kind: str = Field(default="libre", max_length=16)  # libre | flecha
    color: str = Field(default="#E11D48", max_length=9)
    width: float = Field(default=4.0)
    points: List[List[float]] = Field(default_factory=list, sa_column=Column(JSON))
    created_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)
