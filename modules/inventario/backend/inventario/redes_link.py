"""Registra en redes los activos vivos (redes no importa inventario)."""
from sqlmodel import Session, select

from redes.hooks import hooks

from .models import ItAsset


def _assets(session: Session) -> list[ItAsset]:
    return list(session.exec(
        select(ItAsset).where(ItAsset.deleted_at.is_(None)).order_by(ItAsset.asset_tag)
    ).all())


hooks.assets = _assets
