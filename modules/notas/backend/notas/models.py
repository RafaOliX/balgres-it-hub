"""Modelos de notas. Tablas: notas, nota_activos, nota_diagramas, nota_archivos y nota_revisiones (sin FKs a otros módulos)."""
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import JSON, Column, Text
from sqlmodel import Field, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Nota(SQLModel, table=True):
    __tablename__ = "notas"
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str = Field(max_length=200, index=True)
    body: str = Field(default="")  # Markdown
    tags: Optional[List[str]] = Field(default=None, sa_column=Column(JSON))
    # Legado: primer activo vinculado. Los vínculos reales viven en nota_activos.
    asset_tag: Optional[str] = Field(default=None, max_length=64, index=True)
    created_by: str = Field(default="admin", max_length=64)
    updated_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)
    updated_at: datetime = Field(default_factory=_now, index=True)


class NotaActivo(SQLModel, table=True):
    """Activos involucrados en una nota (solo el texto del tag, sin FK a inventario)."""
    __tablename__ = "nota_activos"
    id: Optional[int] = Field(default=None, primary_key=True)
    nota_id: int = Field(foreign_key="notas.id", ondelete="CASCADE", index=True)
    asset_tag: str = Field(max_length=64, index=True)


class NotaDiagrama(SQLModel, table=True):
    """Diagrama de draw.io (XML) asociado a una nota, con vista previa PNG (data URI)."""
    __tablename__ = "nota_diagramas"
    id: Optional[int] = Field(default=None, primary_key=True)
    nota_id: int = Field(foreign_key="notas.id", ondelete="CASCADE", index=True)
    title: str = Field(default="Diagrama", max_length=200)
    xml: str = Field(default="", sa_column=Column(Text))
    preview: Optional[str] = Field(default=None, sa_column=Column(Text))
    created_by: str = Field(default="admin", max_length=64)
    updated_by: str = Field(default="admin", max_length=64)
    updated_at: datetime = Field(default_factory=_now, index=True)


class NotaArchivo(SQLModel, table=True):
    """Archivo adjunto. Vive en UPLOADS_DIR/_private/notas (Caddy no lo sirve; solo la API con token)."""
    __tablename__ = "nota_archivos"
    id: Optional[int] = Field(default=None, primary_key=True)
    nota_id: int = Field(foreign_key="notas.id", ondelete="CASCADE", index=True)
    stored_name: str = Field(max_length=64)
    original_name: str = Field(max_length=255)
    content_type: Optional[str] = Field(default=None, max_length=128)
    size: int = Field(default=0)
    created_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)


class NotaRevision(SQLModel, table=True):
    """Historial: versiones con contenido completo (has_snapshot) y eventos sueltos (archivos, diagramas)."""
    __tablename__ = "nota_revisiones"
    id: Optional[int] = Field(default=None, primary_key=True)
    nota_id: int = Field(foreign_key="notas.id", ondelete="CASCADE", index=True)
    version: int = Field(default=1)
    action: str = Field(max_length=64)
    detail: Optional[str] = Field(default=None, max_length=300)
    has_snapshot: bool = Field(default=False)
    title: Optional[str] = Field(default=None, max_length=200)
    body: Optional[str] = Field(default=None, sa_column=Column(Text))
    tags: Optional[List[str]] = Field(default=None, sa_column=Column(JSON))
    asset_tags: Optional[List[str]] = Field(default=None, sa_column=Column(JSON))
    changed_by: str = Field(default="admin", max_length=64)
    changed_at: datetime = Field(default_factory=_now, index=True)
