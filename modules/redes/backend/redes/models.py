"""Modelos de redes. Tablas nuevas: subnets e ip_addresses (sin FKs a otros módulos)."""
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Subnet(SQLModel, table=True):
    __tablename__ = "subnets"
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(max_length=100)
    cidr: str = Field(unique=True, index=True, max_length=43)
    notes: Optional[str] = Field(default=None)


class IpAddress(SQLModel, table=True):
    __tablename__ = "ip_addresses"
    id: Optional[int] = Field(default=None, primary_key=True)
    ip: str = Field(unique=True, index=True, max_length=45)
    label: Optional[str] = Field(default=None, max_length=128)
    kind: Optional[str] = Field(default=None, max_length=64)
    department: Optional[str] = Field(default=None, max_length=128)
    notes: Optional[str] = Field(default=None)
    # vínculo con inventario (sin FK: el módulo no depende de las tablas de inventario)
    asset_id: Optional[int] = Field(default=None, index=True)
    asset_tag: Optional[str] = Field(default=None, max_length=64)
    mac: Optional[str] = Field(default=None, max_length=32)
    origin: str = Field(default="manual", max_length=16)  # "manual" | "activo"
    is_up: Optional[bool] = Field(default=None)
    last_seen: Optional[datetime] = Field(default=None)
    created_at: datetime = Field(default_factory=_now)
