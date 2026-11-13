"""Router FastAPI del módulo redes (prefijo /api/redes)."""
import asyncio
import ipaddress
import shutil
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, SQLModel, select

from contacts.db import engine, get_session

from . import service
from .models import IpAddress, Subnet

router = APIRouter(prefix="/redes", tags=["redes"])


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def _net(raw: str):
    try:
        return ipaddress.ip_network(raw.strip(), strict=False)
    except ValueError:
        raise HTTPException(422, detail=f"'{raw}' no es una red válida (ej. 192.0.60.0/24)")


def _key(ip: str):
    return ipaddress.ip_address(ip)


class SubnetIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    cidr: str = Field(min_length=1, max_length=43)
    notes: Optional[str] = None


class IpIn(BaseModel):
    ip: str = Field(min_length=1, max_length=45)
    label: Optional[str] = Field(default=None, max_length=128)
    kind: Optional[str] = Field(default=None, max_length=64)
    department: Optional[str] = Field(default=None, max_length=128)
    notes: Optional[str] = None


class ScanIn(BaseModel):
    cidr: str


def _ip_out(r: IpAddress, nets: list[Subnet]) -> dict:
    sub = None
    for s in nets:
        try:
            if _key(r.ip) in _net(s.cidr):
                sub = s.name
                break
        except HTTPException:
            continue
    return {
        "id": r.id, "ip": r.ip, "label": r.label, "kind": r.kind, "department": r.department, "notes": r.notes,
        "asset_tag": r.asset_tag, "mac": r.mac, "origin": r.origin, "is_up": r.is_up,
        "last_seen": r.last_seen.isoformat() if r.last_seen else None, "subnet": sub,
    }


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "redes", "status": "ok"}


# ------------------------------------------------------------------ subredes
@router.get("/subnets")
def listar_subredes(session: Session = Depends(get_session)):
    return [{"id": s.id, "name": s.name, "cidr": s.cidr, "notes": s.notes}
            for s in session.exec(select(Subnet).order_by(Subnet.name)).all()]


@router.post("/subnets", status_code=201)
def crear_subred(payload: SubnetIn, session: Session = Depends(get_session)):
    cidr = str(_net(payload.cidr))
    if session.exec(select(Subnet).where(Subnet.cidr == cidr)).first():
        raise HTTPException(409, detail=f"La red {cidr} ya existe")
    s = Subnet(name=payload.name.strip(), cidr=cidr, notes=payload.notes)
    session.add(s)
    session.commit()
    session.refresh(s)
    return {"id": s.id, "name": s.name, "cidr": s.cidr, "notes": s.notes}


@router.delete("/subnets/{sid}", status_code=204)
def eliminar_subred(sid: int, session: Session = Depends(get_session)):
    s = session.get(Subnet, sid)
    if not s:
        raise HTTPException(404, detail="Subred no encontrada")
    session.delete(s)
    session.commit()


# ------------------------------------------------------------------ IPs
@router.get("/ips")
def listar_ips(q: str | None = None, session: Session = Depends(get_session)):
    nets = list(session.exec(select(Subnet)).all())
    rows = session.exec(select(IpAddress)).all()
    if q:
        t = q.strip().lower()
        rows = [r for r in rows if t in " ".join(str(x or "") for x in (r.ip, r.label, r.kind, r.department, r.asset_tag)).lower()]
    return [_ip_out(r, nets) for r in sorted(rows, key=lambda r: _key(r.ip))]


# IMPORTANTE: /ips/check va antes que /ips/{ip_id}
@router.get("/ips/check")
def verificar_ip(ip: str, asset_tag: str | None = None, session: Session = Depends(get_session)):
    """¿Está libre? Sirve para validar en vivo desde el formulario de activos."""
    ip = service.normalize(ip)
    r = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    libre = r is None or (asset_tag is not None and r.asset_tag == asset_tag)
    return {"ip": ip, "libre": libre, "usada_por": None if libre else (r.asset_tag or r.label)}


@router.post("/ips", status_code=201)
def crear_ip(payload: IpIn, session: Session = Depends(get_session)):
    ip = service.normalize(payload.ip)
    dup = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    if dup:
        raise HTTPException(409, detail=f"La IP {ip} ya está registrada como '{dup.asset_tag or dup.label or 'sin nombre'}'")
    r = IpAddress(ip=ip, label=payload.label, kind=payload.kind, department=payload.department, notes=payload.notes)
    session.add(r)
    session.commit()
    session.refresh(r)
    return _ip_out(r, list(session.exec(select(Subnet)).all()))


@router.put("/ips/{ip_id}")
def actualizar_ip(ip_id: int, payload: IpIn, session: Session = Depends(get_session)):
    r = session.get(IpAddress, ip_id)
    if not r:
        raise HTTPException(404, detail="IP no encontrada")
    ip = service.normalize(payload.ip)
    if ip != r.ip:
        if r.asset_id is not None:
            raise HTTPException(400, detail=f"Pertenece al activo {r.asset_tag}: cambia la IP desde el activo")
        if session.exec(select(IpAddress).where(IpAddress.ip == ip)).first():
            raise HTTPException(409, detail=f"La IP {ip} ya está registrada")
        r.ip = ip
    r.label, r.kind, r.department, r.notes = payload.label, payload.kind, payload.department, payload.notes
    session.add(r)
    session.commit()
    session.refresh(r)
    return _ip_out(r, list(session.exec(select(Subnet)).all()))


@router.delete("/ips/{ip_id}", status_code=204)
def eliminar_ip(ip_id: int, session: Session = Depends(get_session)):
    r = session.get(IpAddress, ip_id)
    if not r:
        raise HTTPException(404, detail="IP no encontrada")
    if r.asset_id is not None:
        raise HTTPException(400, detail=f"Pertenece al activo {r.asset_tag}: se libera al cambiarla o eliminar el activo")
    session.delete(r)
    session.commit()


# ------------------------------------------------------------------ ping
async def _ping(ip: str, sem: asyncio.Semaphore) -> tuple[str, bool]:
    async with sem:
        try:
            p = await asyncio.create_subprocess_exec(
                "ping", "-c", "1", "-W", "1", ip,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
            )
            return ip, (await p.wait()) == 0
        except OSError:
            return ip, False


async def _ping_many(ips: list[str]) -> dict[str, bool]:
    if not shutil.which("ping"):
        raise HTTPException(501, detail="Falta 'ping' en el backend (instala iputils-ping en Dockerfile.backend).")
    sem = asyncio.Semaphore(64)
    return dict(await asyncio.gather(*[_ping(i, sem) for i in ips]))


def _mark(session: Session, rows: list[IpAddress], vivas: set[str]) -> None:
    ahora = datetime.now(timezone.utc)
    for r in rows:
        r.is_up = r.ip in vivas
        if r.is_up:
            r.last_seen = ahora
        session.add(r)
    session.commit()


@router.post("/scan")
async def escanear(payload: ScanIn, session: Session = Depends(get_session)):
    """Barrido ICMP de una red IPv4 (hasta /22). Actualiza el estado de las IPs registradas."""
    net = _net(payload.cidr)
    if net.version != 4 or net.num_addresses > 1024:
        raise HTTPException(422, detail="Usa una red IPv4 de hasta /22 (1024 direcciones)")
    hosts = [str(h) for h in net.hosts()]
    res = await _ping_many(hosts)
    vivas = {ip for ip, ok in res.items() if ok}
    regs = [r for r in session.exec(select(IpAddress)).all() if r.ip in set(hosts)]
    _mark(session, regs, vivas)
    registradas = {r.ip for r in regs}
    return {
        "cidr": str(net), "escaneadas": len(hosts), "vivas": len(vivas),
        "registradas_caidas": [{"ip": r.ip, "nombre": r.asset_tag or r.label} for r in sorted(regs, key=lambda r: _key(r.ip)) if not r.is_up],
        "vivas_sin_registrar": sorted(vivas - registradas, key=_key),
    }


@router.post("/check-registered")
async def verificar_registradas(session: Session = Depends(get_session)):
    """Ping a todas las IPs registradas (IPv4)."""
    rows = [r for r in session.exec(select(IpAddress)).all() if ":" not in r.ip]
    res = await _ping_many([r.ip for r in rows])
    _mark(session, rows, {ip for ip, ok in res.items() if ok})
    caidas = [{"ip": r.ip, "nombre": r.asset_tag or r.label} for r in sorted(rows, key=lambda r: _key(r.ip)) if not r.is_up]
    return {"total": len(rows), "activas": len(rows) - len(caidas), "caidas": caidas}
