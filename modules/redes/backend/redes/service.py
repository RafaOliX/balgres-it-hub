"""Lógica de IPs: validación, unicidad y vínculo con activos (la usa inventario)."""
import ipaddress
from typing import Any

from fastapi import HTTPException
from sqlmodel import Session, select

from .models import IpAddress


def ip_from_specs(specs: dict[str, Any] | None) -> str | None:
    """Devuelve el valor del campo técnico 'IP' (sin importar mayúsculas), si lo hay."""
    for k, v in (specs or {}).items():
        if str(k).strip().lower() == "ip" and str(v or "").strip():
            return str(v).strip()
    return None


def _spec(specs: dict[str, Any] | None, name: str) -> str | None:
    for k, v in (specs or {}).items():
        if str(k).strip().lower() == name and str(v or "").strip():
            return str(v).strip()
    return None


def normalize(raw: str) -> str:
    try:
        return str(ipaddress.ip_address(str(raw).strip()))
    except ValueError:
        raise HTTPException(422, detail=f"'{raw}' no es una dirección IP válida")


def check(session: Session, ip: str, asset_id: int | None = None) -> str:
    """Valida la IP y falla con 409 si la usa otro activo."""
    ip = normalize(ip)
    row = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    if row and row.asset_id is not None and row.asset_id != asset_id:
        quien = row.asset_tag or row.label or "otro registro"
        raise HTTPException(409, detail=f"La IP {ip} ya está en uso por {quien}.")
    return ip


def check_specs(session: Session, specs: dict[str, Any] | None, asset_id: int | None = None) -> None:
    ip = ip_from_specs(specs)
    if ip:
        check(session, ip, asset_id)


def release(session: Session, asset_id: int | None, keep_ip: str | None = None) -> None:
    """Libera las IPs del activo: borra las que creó él y desvincula las manuales."""
    if asset_id is None:
        return
    for row in session.exec(select(IpAddress).where(IpAddress.asset_id == asset_id)).all():
        if keep_ip and row.ip == keep_ip:
            continue
        if row.origin == "activo":
            session.delete(row)
        else:
            row.asset_id = None
            row.asset_tag = None
            session.add(row)


def assign(session: Session, asset) -> None:
    """Sincroniza la IP de los datos técnicos del activo con la tabla de IPs (no hace commit)."""
    ip = ip_from_specs(asset.specs)
    if ip is None:
        release(session, asset.id)
        return
    ip = check(session, ip, asset.id)
    release(session, asset.id, keep_ip=ip)
    row = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    if row is None:
        row = IpAddress(ip=ip, origin="activo", kind=asset.category, label=f"{asset.brand} {asset.model}".strip())
    row.asset_id = asset.id
    row.asset_tag = asset.asset_tag
    row.mac = _spec(asset.specs, "mac")
    session.add(row)
