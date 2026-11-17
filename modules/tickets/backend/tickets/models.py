"""Modelos de tickets. Tablas: tickets, ticket_comentarios y ticket_archivos (sin FKs a otros módulos)."""
from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import Column, Text
from sqlmodel import Field, SQLModel


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Ticket(SQLModel, table=True):
    __tablename__ = "tickets"
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str = Field(max_length=200, index=True)
    description: str = Field(default="")
    status: str = Field(default="Abierto", max_length=32, index=True)
    priority: str = Field(default="Media", max_length=16, index=True)
    category: Optional[str] = Field(default=None, max_length=64)
    requester_id: Optional[int] = Field(default=None, index=True)       # empleado (sin FK)
    requester_name: Optional[str] = Field(default=None, max_length=128)  # copia del nombre
    asset_tag: Optional[str] = Field(default=None, max_length=64, index=True)  # activo (sin FK)
    assignee: Optional[str] = Field(default=None, max_length=64, index=True)   # username del sistema
    due_date: Optional[date] = Field(default=None)
    created_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now, index=True)
    updated_at: datetime = Field(default_factory=_now, index=True)
    resolved_at: Optional[datetime] = Field(default=None)


class TicketComment(SQLModel, table=True):
    """Comentarios y eventos automáticos (cambios de estado, prioridad, responsable...)."""
    __tablename__ = "ticket_comentarios"
    id: Optional[int] = Field(default=None, primary_key=True)
    ticket_id: int = Field(foreign_key="tickets.id", ondelete="CASCADE", index=True)
    kind: str = Field(default="comentario", max_length=16)  # comentario | evento
    body: str = Field(default="", sa_column=Column(Text))
    author: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)


class TicketArchivo(SQLModel, table=True):
    """Adjunto. Vive en UPLOADS_DIR/_private/tickets (Caddy no lo sirve; solo la API con token)."""
    __tablename__ = "ticket_archivos"
    id: Optional[int] = Field(default=None, primary_key=True)
    ticket_id: int = Field(foreign_key="tickets.id", ondelete="CASCADE", index=True)
    stored_name: str = Field(max_length=64)
    original_name: str = Field(max_length=255)
    content_type: Optional[str] = Field(default=None, max_length=128)
    size: int = Field(default=0)
    created_by: str = Field(default="admin", max_length=64)
    created_at: datetime = Field(default_factory=_now)
