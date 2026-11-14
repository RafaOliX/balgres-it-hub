"""Lógica de IPs: validación, unicidad y vínculo con activos (la usa inventario)."""
import ipaddress
import unicodedata
from typing import Any

from fastapi import HTTPException
from sqlmodel import Session, select

from .models import IpAddress


_IP_KEYS = {"ip", "direccion ip", "direccion de ip", "dir ip", "ip address", "ip addr", "ipv4", "ip v4"}
_MAC_KEYS = {"mac", "direccion mac", "dir mac", "mac address", "mac addr"}
_HOST_KEYS = {"hostname", "host name", "host", "nombre de host", "nombre host"}


def _nk(key) -> str:
    """Clave normalizada: sin tildes, minúsculas, sin puntos/guiones y sin espacios repetidos."""
    s = unicodedata.normalize("NFKD", str(key)).encode("ascii", "ignore").decode()
    return " ".join(s.lower().replace(".", " ").replace("_", " ").replace("-", " ").split())


def _spec(specs: dict[str, Any] | None, keys: set[str]) -> str | None:
    """Solo lee los campos de red de la lista: usuarios y claves nunca se tocan."""
    for k, v in (specs or {}).items():
        if _nk(k) in keys and str(v or "").strip():
            return str(v).strip()
    return None


def ip_from_specs(specs: dict[str, Any] | None) -> str | None:
    """Valor del campo técnico de IP (IP, ip, Dirección IP, IP Address...), si lo hay."""
    return _spec(specs, _IP_KEYS)


def mac_from_specs(specs: dict[str, Any] | None) -> str | None:
    return _spec(specs, _MAC_KEYS)


def hostname_from_specs(specs: dict[str, Any] | None) -> str | None:
    return _spec(specs, _HOST_KEYS)


def parse_ip(raw) -> str | None:
    """IP normalizada, o None si no es una dirección válida (DHCP, ap, vacío...)."""
    try:
        return str(ipaddress.ip_address(str(raw).strip()))
    except ValueError:
        return None


def normalize(raw: str) -> str:
    try:
        return str(ipaddress.ip_address(str(raw).strip()))
    except ValueError:
        raise HTTPException(422, detail=f"'{raw}' no es una dirección IP válida")


def _en_uso(ip: str, row: IpAddress) -> str:
    quien = row.asset_tag or row.label or "otro registro"
    if row.is_draft:
        quien += " (borrador)"
    return f"La IP {ip} ya está en uso por {quien}."


def check(session: Session, ip: str, asset_id: int | None = None) -> str:
    """Valida la IP y falla con 409 si la usa otro activo."""
    ip = normalize(ip)
    row = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    if row and row.asset_id is not None and row.asset_id != asset_id:
        raise HTTPException(409, detail=_en_uso(ip, row))
    return ip


def check_specs(session: Session, specs: dict[str, Any] | None, asset_id: int | None = None) -> None:
    """Una IP no válida no bloquea el guardado del activo (simplemente no se reserva)."""
    ip = parse_ip(ip_from_specs(specs) or "")
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
            row.is_draft = False
            session.add(row)


def assign(session: Session, asset) -> None:
    """Sincroniza la IP de los datos técnicos del activo con la tabla de IPs (no hace commit)."""
    raw = ip_from_specs(asset.specs)
    ip = parse_ip(raw) if raw else None
    if ip is None:  # sin IP o IP no válida: no se reserva nada
        release(session, asset.id)
        return
    draft = bool(asset.is_draft)
    row = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    if row is not None and row.asset_id is not None and row.asset_id != asset.id:
        if draft:  # el borrador se guarda sin reservar; el 409 llega al finalizar
            release(session, asset.id)
            return
        raise HTTPException(409, detail=_en_uso(ip, row))
    release(session, asset.id, keep_ip=ip)
    if row is None:
        row = IpAddress(ip=ip, origin="activo", kind=asset.category, label=f"{asset.brand} {asset.model}".strip())
    row.asset_id = asset.id
    row.asset_tag = asset.asset_tag
    row.mac = mac_from_specs(asset.specs)
    row.hostname = hostname_from_specs(asset.specs)
    row.is_draft = draft
    session.add(row)
