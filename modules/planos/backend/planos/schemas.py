"""Schemas Pydantic de planos."""
import re
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

KINDS = {"camara", "nvr", "switch", "ap", "rack", "router", "otro"}
TRAZO_KINDS = {"libre", "flecha"}
MAX_POINTS = 1500


def _blank(v):
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return v


class PlanoUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    notes: Optional[str] = None
    nota_id: Optional[int] = None

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
    nota_id: Optional[int] = None

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


class TrazoIn(BaseModel):
    kind: str = "libre"
    color: str = "#E11D48"
    width: float = Field(default=4.0, ge=0.5, le=30)
    points: List[List[float]]

    @field_validator("kind")
    @classmethod
    def _k(cls, v: str) -> str:
        v = (v or "").strip().lower()
        if v not in TRAZO_KINDS:
            raise ValueError(f"Tipo de trazo no válido. Usa: {', '.join(sorted(TRAZO_KINDS))}")
        return v

    @field_validator("color")
    @classmethod
    def _c(cls, v: str) -> str:
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", v or ""):
            raise ValueError("Color inválido: usa #RRGGBB")
        return v.upper()

    @field_validator("points")
    @classmethod
    def _p(cls, v: List[List[float]]) -> List[List[float]]:
        if len(v) > MAX_POINTS:
            raise ValueError(f"Máximo {MAX_POINTS} puntos por trazo")
        out: List[List[float]] = []
        for q in v:
            if len(q) != 2 or not (0 <= q[0] <= 100 and 0 <= q[1] <= 100):
                raise ValueError("Punto fuera del plano (0-100)")
            out.append([round(q[0], 2), round(q[1], 2)])
        return out

    @model_validator(mode="after")
    def _check(self):
        if self.kind == "flecha" and len(self.points) != 2:
            raise ValueError("La flecha necesita exactamente 2 puntos")
        if self.kind == "libre" and len(self.points) < 2:
            raise ValueError("El trazo necesita al menos 2 puntos")
        return self
