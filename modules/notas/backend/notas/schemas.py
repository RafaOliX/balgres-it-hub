"""Schemas Pydantic de notas."""
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator


class NotaIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = ""
    tags: List[str] = []
    asset_tag: Optional[str] = Field(default=None, max_length=64)

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
        out: list[str] = []
        seen: set[str] = set()
        for s in v or []:
            s = " ".join(str(s).split())[:32]
            if s and s.lower() not in seen:
                seen.add(s.lower())
                out.append(s)
        return out[:20]

    @field_validator("asset_tag")
    @classmethod
    def _asset(cls, v: Optional[str]) -> Optional[str]:
        v = (v or "").strip()
        return v or None


class NotaListItem(BaseModel):
    id: int
    title: str
    snippet: str
    tags: List[str]
    asset_tag: Optional[str]
    updated_by: str
    updated_at: datetime


class NotaRead(BaseModel):
    id: int
    title: str
    body: str
    tags: List[str]
    asset_tag: Optional[str]
    created_by: str
    updated_by: str
    created_at: datetime
    updated_at: datetime
