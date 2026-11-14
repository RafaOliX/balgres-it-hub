"""Router FastAPI del módulo redes (prefijo /api/redes)."""
import asyncio
import ipaddress
import re
import shutil
import socket
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlmodel import Session, SQLModel, select

from contacts.db import engine, get_session

from . import service
from .hooks import hooks
from .models import IpAddress, Subnet

router = APIRouter(prefix="/redes", tags=["redes"])


def _migrate() -> None:
    if engine.dialect.name != "postgresql":
        return  # SQLite: create_all ya crea el esquema completo
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS hostname VARCHAR(128);"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS is_draft BOOLEAN DEFAULT FALSE;"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS first_seen TIMESTAMP;"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS latency_ms DOUBLE PRECISION;"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS ttl INTEGER;"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS open_ports VARCHAR(128);"))
        conn.execute(text("ALTER TABLE ip_addresses ADD COLUMN IF NOT EXISTS dns_name VARCHAR(255);"))


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate()
    try:  # sincronización idempotente; nunca debe impedir el arranque
        with Session(engine) as s:
            _sync_assets(s)
    except Exception:
        pass


def _net(raw: str):
    try:
        return ipaddress.ip_network(raw.strip(), strict=False)
    except ValueError:
        raise HTTPException(422, detail=f"'{raw}' no es una red válida (ej. 192.0.60.0/24)")


def _key(ip: str):
    return ipaddress.ip_address(ip)


def _vkey(ip: str):
    a = ipaddress.ip_address(ip)
    return (a.version, int(a))


def _segment(ip: str) -> str | None:
    """Segmento /24 de una IPv4 (None para IPv6 o texto no válido)."""
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return None
    if a.version != 4:
        return None
    return str(ipaddress.ip_network(f"{a}/24", strict=False))


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
    register: bool = False  # guarda como origen "escaneo" las vivas sin registrar


def _ports(r: IpAddress) -> list[int]:
    return [int(x) for x in (r.open_ports or "").split(",") if x.strip().isdigit()]


def _os_hint(ttl: int | None) -> str | None:
    """Pista por TTL (el valor inicial típico menos los saltos): 64 Linux/red, 128 Windows, 255 red."""
    if ttl is None:
        return None
    if ttl <= 64:
        return "Linux / red"
    if ttl <= 128:
        return "Windows"
    return "Equipo de red"


def _kind_hint(ports) -> str | None:
    s = set(ports or [])
    if 9100 in s:
        return "Impresora"
    if 554 in s:
        return "Cámara / DVR"
    if s & {3389, 445, 135, 139}:
        return "Windows"
    if s & {22, 23}:
        return "Router / equipo de red"
    if s & {80, 443, 8080}:
        return "Equipo con web"
    return None


def _register_found(session: Session, ips: list[str], info: dict) -> None:
    """Guarda las IPs vivas que no estaban registradas (origen "escaneo")."""
    ahora = datetime.now(timezone.utc)
    for ip in ips:
        i = info.get(ip) or {}
        ports = i.get("ports") or []
        session.add(IpAddress(
            ip=ip, origin="escaneo", label=i.get("dns"), kind=_kind_hint(ports), dns_name=i.get("dns"),
            is_up=True, last_seen=ahora, first_seen=ahora, latency_ms=i.get("ms"), ttl=i.get("ttl"),
            open_ports=",".join(str(p) for p in ports) or None,
        ))
    session.commit()


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
        "hostname": r.hostname, "is_draft": bool(r.is_draft), "state": "registrada", "segment": _segment(r.ip),
        "latency_ms": r.latency_ms, "ttl": r.ttl, "open_ports": _ports(r), "dns_name": r.dns_name,
        "first_seen": r.first_seen.isoformat() if r.first_seen else None,
        "os_hint": _os_hint(r.ttl), "kind_hint": _kind_hint(_ports(r)),
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
    all_rows = list(session.exec(select(IpAddress)).all())
    out = [_ip_out(r, nets) for r in sorted(all_rows, key=lambda r: _key(r.ip))]
    out += _virtual_rows(session, all_rows)
    if q:
        t = q.strip().lower()
        keys = ("ip", "label", "kind", "department", "asset_tag", "hostname", "mac", "dns_name", "os_hint", "kind_hint")
        out = [x for x in out if t in " ".join(str(x.get(k) or "") for k in keys).lower()]
    return out


# IMPORTANTE: /ips/check va antes que /ips/{ip_id}
@router.get("/ips/check")
def verificar_ip(ip: str, asset_tag: str | None = None, session: Session = Depends(get_session)):
    """¿Está libre? Sirve para validar en vivo desde el formulario de activos."""
    valida = service.parse_ip(ip)
    if valida is None:
        return {"ip": ip.strip(), "valida": False, "libre": True, "usada_por": None, "vincular": None}
    ip = valida
    r = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
    mio = r is not None and asset_tag is not None and r.asset_tag == asset_tag
    libre = r is None or r.asset_id is None or mio
    usada_por = None
    if not libre:
        usada_por = (r.asset_tag or r.label or "otro registro") + (" (borrador)" if r.is_draft else "")
    vincular = (r.label or "registro manual") if (r is not None and r.asset_id is None) else None
    return {"ip": ip, "valida": True, "libre": libre, "usada_por": usada_por, "vincular": vincular}


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
    if r.origin == "escaneo":
        r.origin = "manual"
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


# ------------------------------------------------------------------ filas calculadas, segmentos /24, duplicadas, sync
class SegmentIn(BaseModel):
    cidr: str = Field(min_length=1, max_length=43)
    name: str = Field(default="", max_length=100)


def _virtual_rows(session: Session, rows: list[IpAddress]) -> list[dict]:
    """Activos con datos de red que no tienen una IP reservada: se muestran sin guardarlos."""
    by_asset = {r.asset_id: r.ip for r in rows if r.asset_id is not None}
    known = {r.ip for r in rows}
    out: list[dict] = []
    for a in hooks.assets(session):
        raw = service.ip_from_specs(a.specs)
        mac = service.mac_from_specs(a.specs)
        host = service.hostname_from_specs(a.specs)
        ip = service.parse_ip(raw) if raw else None
        if ip and by_asset.get(a.id) == ip:
            continue  # ya está registrada a su nombre
        if not (raw or mac or host):
            continue
        if raw is None:
            state = "sin_ip"
        elif ip is None:
            state = "invalida"
        elif ip in known:
            state = "conflicto"
        else:
            state = "pendiente"
        out.append({
            "id": -a.id, "ip": ip or raw or "", "label": f"{a.brand} {a.model}".strip(), "kind": a.category,
            "department": None, "notes": None, "asset_tag": a.asset_tag, "mac": mac, "hostname": host,
            "origin": "activo", "is_up": None, "last_seen": None, "subnet": None, "segment": None,
            "is_draft": bool(a.is_draft), "state": state,
        })
    return out


def _seg24(raw: str):
    net = _net(raw)
    if net.version != 4 or net.prefixlen != 24:
        raise HTTPException(422, detail="Los segmentos son redes IPv4 /24 (ej. 192.0.60.0/24)")
    return ipaddress.ip_network(f"{net.network_address}/24", strict=False)


@router.get("/segments")
def segmentos(session: Session = Depends(get_session)):
    """Agrupa las IPs por /24 sin registrar nada a mano. El nombre vive en la tabla subnets."""
    def blank(cidr: str, name: str | None) -> dict:
        return {"cidr": cidr, "name": name, "usadas": 0, "libres": 254, "en_linea": 0,
                "sin_respuesta": 0, "sin_verificar": 0, "borradores": 0}

    segs: dict[str, dict] = {}
    for s in session.exec(select(Subnet)).all():
        try:
            n = ipaddress.ip_network(s.cidr, strict=False)
        except ValueError:
            continue
        if n.version == 4 and n.prefixlen == 24:
            segs[str(n)] = blank(str(n), s.name)
    for r in session.exec(select(IpAddress)).all():
        seg = _segment(r.ip)
        if seg is None:
            continue
        d = segs.setdefault(seg, blank(seg, None))
        d["usadas"] += 1
        if r.is_draft:
            d["borradores"] += 1
        if r.is_up is True:
            d["en_linea"] += 1
        elif r.is_up is False:
            d["sin_respuesta"] += 1
        else:
            d["sin_verificar"] += 1
    for d in segs.values():
        d["libres"] = max(0, 254 - d["usadas"])
    return sorted(segs.values(), key=lambda d: ipaddress.ip_network(d["cidr"]))


@router.put("/segments")
def nombrar_segmento(payload: SegmentIn, session: Session = Depends(get_session)):
    """Pone nombre a un /24 (upsert en subnets). Nombre vacío = quitarlo."""
    cidr = str(_seg24(payload.cidr))
    name = payload.name.strip()
    s = session.exec(select(Subnet).where(Subnet.cidr == cidr)).first()
    if not name:
        if s:
            session.delete(s)
            session.commit()
        return {"cidr": cidr, "name": None}
    if s:
        s.name = name
    else:
        s = Subnet(name=name, cidr=cidr)
    session.add(s)
    session.commit()
    return {"cidr": cidr, "name": name}


@router.get("/duplicates")
def duplicadas(session: Session = Depends(get_session)):
    """IPs repetidas en los datos técnicos de los activos (la tabla solo guarda una por IP)."""
    grupos: dict[str, list[dict]] = {}
    for a in hooks.assets(session):
        raw = service.ip_from_specs(a.specs)
        ip = service.parse_ip(raw) if raw else None
        if ip:
            grupos.setdefault(ip, []).append({
                "tag": a.asset_tag, "borrador": bool(a.is_draft), "equipo": f"{a.category} {a.brand} {a.model}".strip(),
            })
    return [{"ip": ip, "activos": v} for ip, v in sorted(grupos.items(), key=lambda kv: _vkey(kv[0])) if len(v) > 1]


def _sync_assets(session: Session) -> dict:
    registradas, no_validas, conflictos = 0, 0, []
    for a in hooks.assets(session):
        raw = service.ip_from_specs(a.specs)
        if not raw:
            continue
        ip = service.parse_ip(raw)
        if ip is None:
            no_validas += 1
            continue
        try:
            service.assign(session, a)
            session.flush()
        except HTTPException as e:
            conflictos.append({"tag": a.asset_tag, "ip": raw, "detalle": str(e.detail)})
            continue
        row = session.exec(select(IpAddress).where(IpAddress.ip == ip)).first()
        if row is not None and row.asset_id == a.id:
            registradas += 1
        else:
            conflictos.append({"tag": a.asset_tag, "ip": raw, "detalle": f"La IP {ip} ya está reservada por otro registro."})
    session.commit()
    return {"registradas": registradas, "no_validas": no_validas, "conflictos": conflictos}


@router.post("/sync")
def sincronizar(session: Session = Depends(get_session)):
    """Registra las IPs de todos los activos (borradores incluidos). Es idempotente."""
    return _sync_assets(session)


# ------------------------------------------------------------------ ping
_TCP_PORTS = (80, 443, 22, 23, 53, 135, 139, 445, 554, 3389, 8080, 9100)
_RE_TTL = re.compile(r"ttl=(\d+)", re.I)
_RE_MS = re.compile(r"time[=<]([\d.]+)", re.I)


async def _icmp(ip: str) -> dict | None:
    """Un ping ICMP. Un "host inaccesible" (respuesta de otro equipo) devuelve código != 0, así que cuenta como sin respuesta."""
    try:
        p = await asyncio.create_subprocess_exec(
            "ping", "-c", "1", "-W", "1", ip,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await p.communicate()
    except OSError:
        return None
    if p.returncode != 0:
        return None
    txt = out.decode(errors="ignore")
    ttl, ms = _RE_TTL.search(txt), _RE_MS.search(txt)
    return {"ttl": int(ttl.group(1)) if ttl else None, "ms": float(ms.group(1)) if ms else None}


async def _tcp_state(ip: str, port: int):
    """("open"|"closed", ms) si el equipo contesta (abierto o RST); None si no hay respuesta."""
    t0 = time.monotonic()
    try:
        _, w = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=0.8)
    except ConnectionRefusedError:
        return "closed", (time.monotonic() - t0) * 1000
    except (asyncio.TimeoutError, OSError):
        return None
    w.close()
    return "open", (time.monotonic() - t0) * 1000


async def _dns(ip: str) -> str | None:
    try:
        loop = asyncio.get_running_loop()
        return (await asyncio.wait_for(loop.run_in_executor(None, socket.gethostbyaddr, ip), timeout=1.5))[0]
    except Exception:
        return None


async def _probe(ip: str, sem: asyncio.Semaphore) -> tuple[str, dict | None]:
    """ICMP y TCP en paralelo. None = sin respuesta; si vive devuelve {ms, ttl, ports, dns}."""
    async with sem:
        icmp, tcps = await asyncio.gather(_icmp(ip), asyncio.gather(*[_tcp_state(ip, pt) for pt in _TCP_PORTS]))
        if icmp is None and not any(tcps):
            return ip, None
        abiertos = [pt for pt, st in zip(_TCP_PORTS, tcps) if st and st[0] == "open"]
        ms = icmp["ms"] if icmp else None
        if ms is None:
            tms = [st[1] for st in tcps if st]
            ms = round(min(tms), 1) if tms else None
        return ip, {"ms": ms, "ttl": icmp["ttl"] if icmp else None, "ports": abiertos, "dns": await _dns(ip)}


async def _ping_many(ips: list[str]) -> dict[str, dict | None]:
    if not shutil.which("ping"):
        raise HTTPException(501, detail="Falta 'ping' en el backend (instala iputils-ping en Dockerfile.backend).")
    sem = asyncio.Semaphore(32)
    return dict(await asyncio.gather(*[_probe(i, sem) for i in ips]))


def _mark(session: Session, rows: list[IpAddress], vivas: set[str], info: dict | None = None) -> None:
    ahora = datetime.now(timezone.utc)
    for r in rows:
        r.is_up = r.ip in vivas
        if r.is_up:
            r.last_seen = ahora
            if r.first_seen is None:
                r.first_seen = ahora
            i = (info or {}).get(r.ip) or {}
            if i:
                r.latency_ms = i.get("ms")
                r.ttl = i.get("ttl")
                r.open_ports = ",".join(str(p) for p in i.get("ports") or []) or None
                if i.get("dns"):
                    r.dns_name = i["dns"]
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
    _mark(session, regs, vivas, res)
    registradas = {r.ip for r in regs}
    nuevas = sorted(vivas - registradas, key=_key)
    if payload.register:
        _register_found(session, nuevas, res)
    return {
        "cidr": str(net), "escaneadas": len(hosts), "vivas": len(vivas),
        "registradas_caidas": [{"ip": r.ip, "nombre": r.asset_tag or r.label} for r in sorted(regs, key=lambda r: _key(r.ip)) if not r.is_up],
        "vivas_sin_registrar": [] if payload.register else nuevas,
        "nuevas_registradas": len(nuevas) if payload.register else 0,
    }


async def _verify_registered(session: Session) -> dict:
    rows = [r for r in session.exec(select(IpAddress)).all() if ":" not in r.ip]
    res = await _ping_many([r.ip for r in rows])
    _mark(session, rows, {ip for ip, ok in res.items() if ok}, res)
    caidas = [{"ip": r.ip, "nombre": r.asset_tag or r.label} for r in sorted(rows, key=lambda r: _key(r.ip)) if not r.is_up]
    return {"total": len(rows), "activas": len(rows) - len(caidas), "caidas": caidas}


@router.post("/check-registered")
async def verificar_registradas(session: Session = Depends(get_session)):
    """Ping a todas las IPs registradas (IPv4)."""
    return await _verify_registered(session)


async def periodic_ping(minutes: int) -> None:
    """Tarea de fondo (la arranca main.py). REDES_PING_MINUTES=0 la apaga."""
    await asyncio.sleep(30)
    while True:
        try:
            with Session(engine) as s:
                await _verify_registered(s)
        except asyncio.CancelledError:
            raise
        except Exception:
            pass
        await asyncio.sleep(max(1, minutes) * 60)
