"""Schemas Pydantic de tickets."""
from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

Status = Literal["Abierto", "En curso", "En espera", "Resuelto", "Cerrado"]
Priority = Literal["Baja", "Media", "Alta", "Crítica"]


def _blank(v):
    if isinstance(v, str):
        v = " ".join(v.split())
        return v or None
    return v


class TicketIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = ""
    status: Status = "Abierto"
    priority: Priority = "Media"
    category: Optional[str] = Field(default=None, max_length=64)
    requester_id: Optional[int] = None
    requester_name: Optional[str] = Field(default=None, max_length=128)
    asset_tag: Optional[str] = Field(default=None, max_length=64)
    assignee: Optional[str] = Field(default=None, max_length=64)
    due_date: Optional[date] = None

    @field_validator("title")
    @classmethod
    def _t(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("El título es obligatorio")
        return v

    @field_validator("category", "requester_name", "asset_tag", "assignee")
    @classmethod
    def _b(cls, v):
        return _blank(v)


class CommentIn(BaseModel):
    body: str = Field(min_length=1, max_length=10000)

    @field_validator("body")
    @classmethod
    def _body(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("El comentario está vacío")
        return v
