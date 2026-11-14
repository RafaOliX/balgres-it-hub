"""Registra en contacts lo que depende de los activos (contadores y validaciones)."""
from sqlalchemy import func
from sqlmodel import Session, select

from contacts.hooks import hooks

from .models import ItAsset, ItAssetAssignment


def _asset_counts(session: Session, emp_id: int | None = None) -> dict[int, int]:
    stmt = select(ItAsset.employee_id, func.count()).where(
        ItAsset.employee_id.is_not(None), ItAsset.deleted_at.is_(None), ItAsset.is_draft == False  # noqa: E712
    )
    if emp_id is not None:
        stmt = stmt.where(ItAsset.employee_id == emp_id)
    return {k: n for k, n in session.exec(stmt.group_by(ItAsset.employee_id)).all()}


def _open_assets(session: Session, emp_id: int) -> int:
    return session.exec(
        select(func.count()).select_from(ItAsset).where(ItAsset.employee_id == emp_id, ItAsset.deleted_at.is_(None))
    ).one()


def _has_history(session: Session, emp_id: int) -> bool:
    return bool(
        session.exec(select(ItAssetAssignment).where(ItAssetAssignment.employee_id == emp_id)).first()
        or session.exec(select(ItAsset).where(ItAsset.employee_id == emp_id)).first()
    )


def _renamed(session: Session, emp_id: int, name: str) -> None:
    for a in session.exec(select(ItAsset).where(ItAsset.employee_id == emp_id)).all():
        a.assigned_to = name
        session.add(a)


hooks.asset_counts = _asset_counts
hooks.open_assets = _open_assets
hooks.has_history = _has_history
hooks.renamed = _renamed
