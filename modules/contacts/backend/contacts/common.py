"""Utilidades compartidas (las reutiliza inventario)."""
from fastapi import Header
from sqlmodel import Session, select

from .models import Location


def current_user(x_auth_user: str | None = Header(default=None)) -> str:
    """Usuario autenticado. Caddy lo inyecta en X-Auth-User (ver Caddyfile.prod)."""
    return ((x_auth_user or "admin").strip() or "admin")[:64]


def location_paths(session: Session) -> dict[int, str]:
    """Devuelve {id: 'Sede › Área › Oficina'}."""
    locs = session.exec(select(Location)).all()
    by_id = {l.id: l for l in locs}
    out: dict[int, str] = {}
    for l in locs:
        parts, cur, guard = [], l, 0
        while cur is not None and guard < 12:
            parts.append(cur.name)
            cur = by_id.get(cur.parent_id) if cur.parent_id else None
            guard += 1
        out[l.id] = " › ".join(reversed(parts))
    return out
