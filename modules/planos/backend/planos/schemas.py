"""Schemas Pydantic de planos."""
from typing import Optional

from pydantic import BaseModel, Field, field_validator

KINDS = {"camara", "nvr", "switch", "ap", "rack", "router", "otro"}


def _blank(v):
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return v


class PlanoUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    notes: Optional[str] = None

    @field_validator("name")
    @classmethod
    def _n(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("El nombre es obligatorio")
        return v

    @field_validator("notes")
    @classmethod
    def _no(cls, v):
        return _blank(v)


class PinIn(BaseModel):
    x: float = Field(ge=0, le=100)
    y: float = Field(ge=0, le=100)
    kind: str = "camara"
    label: Optional[str] = Field(default=None, max_length=128)
    asset_tag: Optional[str] = Field(default=None, max_length=64)
    notes: Optional[str] = None

    @field_validator("kind")
    @classmethod
    def _k(cls, v: str) -> str:
        v = (v or "").strip().lower()
        if v not in KINDS:
            raise ValueError(f"Tipo no válido. Usa: {', '.join(sorted(KINDS))}")
        return v

    @field_validator("label", "asset_tag", "notes")
    @classmethod
    def _b(cls, v):
        return _blank(v)
