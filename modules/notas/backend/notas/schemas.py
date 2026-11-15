"""Schemas Pydantic de notas."""
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator


def _dedupe(items: List[str], limit: int, maxlen: int) -> List[str]:
    out: list[str] = []
    seen: set[str] = set()
    for s in items or []:
        s = " ".join(str(s).split())[:maxlen]
        if s and s.casefold() not in seen:
            seen.add(s.casefold())
            out.append(s)
    return out[:limit]


class NotaIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = ""
    tags: List[str] = []
    asset_tag: Optional[str] = Field(default=None, max_length=64)  # legado: se fusiona en asset_tags
    asset_tags: List[str] = []

    @field_validator("title")
    @classmethod
    def _title(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("El título es obligatorio")
        return v

    @field_validator("tags")
    @classmethod
    def _tags(cls, v: List[str]) -> List[str]:
        return _dedupe(v, 20, 32)

    @field_validator("asset_tag")
    @classmethod
    def _asset(cls, v: Optional[str]) -> Optional[str]:
        v = (v or "").strip()
        return v or None

    @field_validator("asset_tags")
    @classmethod
    def _assets(cls, v: List[str]) -> List[str]:
        return _dedupe(v, 50, 64)

    @model_validator(mode="after")
    def _merge_legacy(self):
        if self.asset_tag:
            self.asset_tags = _dedupe([self.asset_tag, *self.asset_tags], 50, 64)
        return self


class NotaListItem(BaseModel):
    id: int
    title: str
    snippet: str
    tags: List[str]
    asset_tag: Optional[str]
    asset_tags: List[str] = []
    diagram_count: int = 0
    updated_by: str
    updated_at: datetime


class NotaRead(BaseModel):
    id: int
    title: str
    body: str
    tags: List[str]
    asset_tag: Optional[str]
    asset_tags: List[str] = []
    created_by: str
    updated_by: str
    created_at: datetime
    updated_at: datetime


class DiagramaIn(BaseModel):
    title: str = Field(default="Diagrama", max_length=200)
    xml: str = Field(default="", max_length=2_000_000)

    @field_validator("title")
    @classmethod
    def _t(cls, v: str) -> str:
        return " ".join((v or "").split()) or "Diagrama"
