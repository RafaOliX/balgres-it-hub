"""Ubicaciones, custodia de equipos por empleado y dashboard (los empleados viven en contacts)."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_
from sqlmodel import Session, select

from .common import current_user, location_paths
from .db import get_session
from .models import Employee, ItAsset, ItAssetAssignment, ItAssetHistory, Location
from .schemas import ItAssetRead, LocationCreate, LocationRead

router = APIRouter()


def _norm(s: str) -> str:
    return " ".join(s.split())


def _loc_read(l: Location, paths: dict[int, str]) -> LocationRead:
    return LocationRead(id=l.id, name=l.name, parent_id=l.parent_id, kind=l.kind, full_name=paths.get(l.id, l.name))


def _resync_assets(session: Session) -> None:
    """El texto asset.location se deriva de location_id: refrescarlo si cambian nombres/jerarquía."""
    paths = location_paths(session)
    for a in session.exec(select(ItAsset).where(ItAsset.location_id.is_not(None))).all():
        nuevo = paths.get(a.location_id)
        if nuevo and a.location != nuevo:
            a.location = nuevo
            session.add(a)


def _check_loc(session: Session, payload: LocationCreate, loc_id: int | None = None) -> str:
    name = _norm(payload.name)
    if not name:
        raise HTTPException(400, detail="El nombre es obligatorio")
    if payload.parent_id is not None:
        if not session.get(Location, payload.parent_id):
            raise HTTPException(404, detail="Ubicación padre no encontrada")
        cur, guard = session.get(Location, payload.parent_id), 0
        while cur is not None and loc_id is not None and guard < 20:
            if cur.id == loc_id:
                raise HTTPException(400, detail="Una ubicación no puede colgar de sí misma ni de una descendiente")
            cur = session.get(Location, cur.parent_id) if cur.parent_id else None
            guard += 1
    for s in session.exec(select(Location).where(Location.parent_id == payload.parent_id)).all():
        if s.id != loc_id and s.name.lower() == name.lower():
            raise HTTPException(409, detail=f"Ya existe '{name}' en ese nivel")
    return name


# ------------------------------------------------------------------ ubicaciones
@router.get("/locations", response_model=list[LocationRead])
def listar_ubicaciones(session: Session = Depends(get_session)):
    paths = location_paths(session)
    locs = session.exec(select(Location)).all()
    return sorted((_loc_read(l, paths) for l in locs), key=lambda x: x.full_name.lower())


@router.post("/locations", response_model=LocationRead, status_code=201)
def crear_ubicacion(payload: LocationCreate, session: Session = Depends(get_session)):
    name = _check_loc(session, payload)
    loc = Location(name=name, parent_id=payload.parent_id, kind=payload.kind)
    session.add(loc)
    session.commit()
    session.refresh(loc)
    return _loc_read(loc, location_paths(session))


@router.put("/locations/{loc_id}", response_model=LocationRead)
def actualizar_ubicacion(loc_id: int, payload: LocationCreate, session: Session = Depends(get_session)):
    loc = session.get(Location, loc_id)
    if not loc:
        raise HTTPException(404, detail="Ubicación no encontrada")
    loc.name = _check_loc(session, payload, loc_id)
    loc.parent_id = payload.parent_id
    loc.kind = payload.kind
    session.add(loc)
    session.flush()
    _resync_assets(session)
    session.commit()
    session.refresh(loc)
    return _loc_read(loc, location_paths(session))


@router.delete("/locations/{loc_id}", status_code=204)
def eliminar_ubicacion(loc_id: int, session: Session = Depends(get_session)):
    loc = session.get(Location, loc_id)
    if not loc:
        raise HTTPException(404, detail="Ubicación no encontrada")
    if session.exec(select(Location).where(Location.parent_id == loc_id)).first():
        raise HTTPException(400, detail="Tiene sububicaciones. Elimínalas o muévelas primero")
    if session.exec(select(ItAsset).where(ItAsset.location_id == loc_id)).first():
        raise HTTPException(400, detail="Hay activos en esta ubicación")
    session.delete(loc)
    session.commit()


@router.post("/locations/import-from-assets")
def importar_ubicaciones(session: Session = Depends(get_session)):
    """Crea ubicaciones desde el texto libre actual, unificando 'Sistemas', 'sistemas ' y 'SISTEMAS'."""
    assets = session.exec(
        select(ItAsset).where(ItAsset.location.is_not(None), ItAsset.location_id.is_(None))
    ).all()
    existentes = {_norm(l.name).lower(): l for l in session.exec(select(Location).where(Location.parent_id.is_(None))).all()}
    creadas, vinculados = 0, 0
    for a in assets:
        texto = _norm(a.location or "")
        if not texto:
            continue
        loc = existentes.get(texto.lower())
        if loc is None:
            loc = Location(name=texto)
            session.add(loc)
            session.flush()
            existentes[texto.lower()] = loc
            creadas += 1
        a.location_id = loc.id
        a.location = loc.name
        session.add(a)
        vinculados += 1
    session.commit()
    return {"ubicaciones_creadas": creadas, "activos_vinculados": vinculados}


# ------------------------------------------------------------------ empleados: importar desde activos
@router.post("/employees/import-from-assets")
def importar_empleados(session: Session = Depends(get_session)):
    """Crea empleados desde 'assigned_to' y registra su asignación vigente."""
    assets = session.exec(
        select(ItAsset).where(ItAsset.assigned_to.is_not(None), ItAsset.employee_id.is_(None))
    ).all()
    existentes = {_norm(e.name).lower(): e for e in session.exec(select(Employee)).all()}
    creados, vinculados = 0, 0
    for a in assets:
        texto = _norm(a.assigned_to or "")
        if not texto:
            continue
        emp = existentes.get(texto.lower())
        if emp is None:
            emp = Employee(name=texto)
            session.add(emp)
            session.flush()
            existentes[texto.lower()] = emp
            creados += 1
        a.employee_id = emp.id
        a.assigned_to = emp.name
        session.add(a)
        session.add(ItAssetAssignment(
            asset_id=a.id, employee_id=emp.id, employee_name=emp.name,
            assigned_at=a.created_at, delivered_by="importación", notes="Asignación previa importada",
        ))
        vinculados += 1
    session.commit()
    return {"empleados_creados": creados, "activos_vinculados": vinculados}


# ------------------------------------------------------------------ dashboard
@router.get("/dashboard")
def dashboard(session: Session = Depends(get_session)):
    """Agregados en SQL: no carga los activos en memoria."""
    live = ItAsset.deleted_at.is_(None)
    final = (live, ItAsset.is_draft == False)  # noqa: E712

    def count(*conds):
        return session.exec(select(func.count()).select_from(ItAsset).where(*conds)).one()

    def group(col, label, limit=None):
        key = func.coalesce(col, label)
        q = select(key, func.count()).where(*final).group_by(key).order_by(func.count().desc())
        if limit:
            q = q.limit(limit)
        return {k: n for k, n in session.exec(q).all()}

    total = count(*final)
    asignados = count(*final, or_(ItAsset.employee_id.is_not(None), ItAsset.assigned_to.is_not(None)))
    return {
        "total": total,
        "borradores": count(live, ItAsset.is_draft == True),  # noqa: E712
        "unidades_totales": int(session.exec(select(func.coalesce(func.sum(ItAsset.quantity), 0)).where(*final)).one()),
        "asignados": asignados,
        "sin_asignar": total - asignados,
        "por_estado": group(ItAsset.status, "Sin estado"),
        "por_categoria": group(ItAsset.category, "Sin categoría"),
        "por_ubicacion": group(ItAsset.location, "Sin ubicación", 8),
    }


# ------------------------------------------------------------------ custodia por empleado
def _emp_or_404(session: Session, emp_id: int) -> Employee:
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    return emp


def _assigned(session: Session, emp_id: int) -> list[ItAsset]:
    return list(session.exec(
        select(ItAsset).where(ItAsset.employee_id == emp_id, ItAsset.deleted_at.is_(None)).order_by(ItAsset.asset_tag)
    ).all())


@router.get("/employees/{emp_id}/assets", response_model=list[ItAssetRead])
def empleado_activos(emp_id: int, session: Session = Depends(get_session)):
    _emp_or_404(session, emp_id)
    return [a for a in _assigned(session, emp_id) if not a.is_draft]


@router.get("/employees/{emp_id}/history")
def empleado_historial(emp_id: int, session: Session = Depends(get_session)):
    _emp_or_404(session, emp_id)
    rows = session.exec(
        select(ItAssetAssignment).where(ItAssetAssignment.employee_id == emp_id).order_by(ItAssetAssignment.assigned_at.desc())
    ).all()
    ids = {r.asset_id for r in rows}
    assets = {a.id: a for a in session.exec(select(ItAsset).where(ItAsset.id.in_(ids))).all()} if ids else {}
    out = []
    for r in rows:
        a = assets.get(r.asset_id)
        out.append({
            "asset_tag": a.asset_tag if a else "(eliminado)",
            "equipo": f"{a.category} {a.brand} {a.model}".strip() if a else "",
            "assigned_at": r.assigned_at.isoformat(),
            "returned_at": r.returned_at.isoformat() if r.returned_at else None,
            "delivered_by": r.delivered_by,
            "notes": r.notes,
            "return_notes": r.return_notes,
        })
    return out


# ------------------------------------------------------------------ baja y traspaso
class _NotesIn(BaseModel):
    notes: str | None = None


class _TransferIn(BaseModel):
    to_employee_id: int
    notes: str | None = None


def _liberar(session: Session, a: ItAsset, ahora, notes: str | None, user: str, nuevo: Employee | None = None) -> None:
    for x in session.exec(select(ItAssetAssignment).where(
        ItAssetAssignment.asset_id == a.id, ItAssetAssignment.returned_at.is_(None)
    )).all():
        x.returned_at = ahora
        x.return_notes = notes
        session.add(x)
    anterior = a.assigned_to
    if nuevo is not None:
        session.add(ItAssetAssignment(
            asset_id=a.id, employee_id=nuevo.id, employee_name=nuevo.name,
            assigned_at=ahora, delivered_by=user, notes=notes,
        ))
        a.employee_id, a.assigned_to = nuevo.id, nuevo.name
    else:
        a.employee_id, a.assigned_to = None, None
    session.add(ItAssetHistory(asset_id=a.id, field_name="asignado_a", old_value=anterior, new_value=a.assigned_to, changed_by=user))
    session.add(a)


@router.post("/employees/{emp_id}/offboard")
def empleado_baja(emp_id: int, payload: _NotesIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    """Devuelve todos sus equipos y lo deja inactivo."""
    emp = _emp_or_404(session, emp_id)
    ahora = datetime.now(timezone.utc)
    assets = _assigned(session, emp_id)
    nota = (payload.notes or "").strip() or "Baja del empleado"
    for a in assets:
        _liberar(session, a, ahora, nota, user)
    emp.active = False
    session.add(emp)
    session.commit()
    return {"devueltos": len(assets)}


@router.post("/employees/{emp_id}/transfer")
def empleado_traspaso(emp_id: int, payload: _TransferIn, session: Session = Depends(get_session), user: str = Depends(current_user)):
    """Pasa todos los equipos de un empleado a otro."""
    emp = _emp_or_404(session, emp_id)
    dest = _emp_or_404(session, payload.to_employee_id)
    if dest.id == emp.id:
        raise HTTPException(400, detail="El destino es el mismo empleado")
    if not dest.active:
        raise HTTPException(400, detail="El empleado destino está inactivo")
    ahora = datetime.now(timezone.utc)
    nota = (payload.notes or "").strip() or f"Traspaso desde {emp.name}"
    assets = _assigned(session, emp_id)
    for a in assets:
        _liberar(session, a, ahora, nota, user, nuevo=dest)
    session.commit()
    return {"traspasados": len(assets)}
