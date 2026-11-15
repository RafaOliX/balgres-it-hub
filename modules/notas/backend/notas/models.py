"""Modelos de notas. Tabla nueva: notas (sin FKs a otros módulos)."""
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Nota(SQLModel, table=True):
    __tablename__ = "notas"
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str = Field(max_length=200, index=True)
    body: str = Field(default="")
    tags: Optional[List[str]] = Field(default=None, sa_column=Column(JSON))
    # vínculo opcional con inventario (solo el texto del tag, sin FK)
    asset_tag: Optional[str] = Field(default=None, max_length=64, index=True)
    created_by: str = Field(default="admin", max_length=64)
    updated_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)
    updated_at: datetime = Field(default_factory=_now, index=True)
