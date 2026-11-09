"""Catálogos (ubicaciones, empleados) y dashboard."""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from .common import location_paths
from .db import get_session
from .models import Employee, ItAsset, ItAssetAssignment, Location
from .schemas import EmployeeCreate, EmployeeRead, LocationCreate, LocationRead

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


# ------------------------------------------------------------------ empleados
@router.get("/employees", response_model=list[EmployeeRead])
def listar_empleados(solo_activos: bool = False, session: Session = Depends(get_session)):
    stmt = select(Employee).order_by(Employee.name)
    if solo_activos:
        stmt = stmt.where(Employee.active == True)  # noqa: E712
    return list(session.exec(stmt).all())


@router.post("/employees", response_model=EmployeeRead, status_code=201)
def crear_empleado(payload: EmployeeCreate, session: Session = Depends(get_session)):
    name = _norm(payload.name)
    dup = session.exec(select(Employee).where(Employee.name.ilike(name))).first()
    if dup:
        raise HTTPException(409, detail=f"Ya existe el empleado '{dup.name}'")
    emp = Employee(**{**payload.model_dump(), "name": name})
    session.add(emp)
    session.commit()
    session.refresh(emp)
    return emp


@router.put("/employees/{emp_id}", response_model=EmployeeRead)
def actualizar_empleado(emp_id: int, payload: EmployeeCreate, session: Session = Depends(get_session)):
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    name = _norm(payload.name)
    dup = session.exec(select(Employee).where(Employee.name.ilike(name))).first()
    if dup and dup.id != emp_id:
        raise HTTPException(409, detail=f"Ya existe el empleado '{dup.name}'")
    renombrado = emp.name != name
    for k, v in payload.model_dump().items():
        setattr(emp, k, v)
    emp.name = name
    session.add(emp)
    if renombrado:
        for a in session.exec(select(ItAsset).where(ItAsset.employee_id == emp_id)).all():
            a.assigned_to = name
            session.add(a)
    session.commit()
    session.refresh(emp)
    return emp


@router.delete("/employees/{emp_id}", status_code=204)
def eliminar_empleado(emp_id: int, session: Session = Depends(get_session)):
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    if (
        session.exec(select(ItAssetAssignment).where(ItAssetAssignment.employee_id == emp_id)).first()
        or session.exec(select(ItAsset).where(ItAsset.employee_id == emp_id)).first()
    ):
        raise HTTPException(400, detail="Tiene historial de asignaciones. Márcalo como inactivo en vez de eliminarlo")
    session.delete(emp)
    session.commit()


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
    hoy = date.today()
    todos = session.exec(select(ItAsset).where(ItAsset.deleted_at.is_(None))).all()
    finales = [a for a in todos if not a.is_draft]

    por_estado: dict[str, int] = {}
    por_categoria: dict[str, int] = {}
    por_ubicacion: dict[str, int] = {}
    for a in finales:
        k = a.status or "Sin estado"
        por_estado[k] = por_estado.get(k, 0) + 1
        por_categoria[a.category] = por_categoria.get(a.category, 0) + 1
        u = a.location or "Sin ubicación"
        por_ubicacion[u] = por_ubicacion.get(u, 0) + 1

    garantias = sorted(
        (
            {
                "tag": a.asset_tag,
                "equipo": f"{a.category} {a.brand} {a.model}".strip(),
                "vence": a.warranty_until.isoformat(),
                "dias": (a.warranty_until - hoy).days,
            }
            for a in finales
            if a.warranty_until and 0 <= (a.warranty_until - hoy).days <= 60
        ),
        key=lambda x: x["dias"],
    )
    asignados = sum(1 for a in finales if a.employee_id or a.assigned_to)
    return {
        "total": len(finales),
        "borradores": len(todos) - len(finales),
        "unidades_totales": sum(a.quantity or 0 for a in finales),
        "asignados": asignados,
        "sin_asignar": len(finales) - asignados,
        "costo_total": round(sum(a.cost or 0 for a in finales), 2),
        "garantias_vencidas": sum(1 for a in finales if a.warranty_until and a.warranty_until < hoy),
        "garantias_por_vencer": garantias,
        "por_estado": por_estado,
        "por_categoria": dict(sorted(por_categoria.items(), key=lambda kv: -kv[1])),
        "por_ubicacion": dict(sorted(por_ubicacion.items(), key=lambda kv: -kv[1])[:8]),
    }
