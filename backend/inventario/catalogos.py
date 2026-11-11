"""Catálogos (ubicaciones, empleados) y dashboard."""
from datetime import date, datetime, timezone
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from fpdf import FPDF
from pydantic import BaseModel
from sqlalchemy import func, or_
from sqlmodel import Session, select

from .common import current_user, location_paths
from .db import get_session
from .models import Employee, ItAsset, ItAssetAssignment, ItAssetHistory, Location
from .schemas import EmployeeCreate, EmployeeRead, ItAssetRead, LocationCreate, LocationRead

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


def _check_employee(session: Session, payload: EmployeeCreate, emp_id: int | None = None) -> str:
    name = _norm(payload.name)
    code = (payload.employee_code or "").strip().lower()
    mail = (payload.email or "").strip().lower()
    for e in session.exec(select(Employee)).all():
        if e.id == emp_id:
            continue
        if code and (e.employee_code or "").strip().lower() == code:
            raise HTTPException(409, detail=f"El código '{payload.employee_code}' ya lo usa {e.name}")
        if mail and (e.email or "").strip().lower() == mail:
            raise HTTPException(409, detail=f"El correo '{payload.email}' ya lo usa {e.name}")
        if payload.active and payload.extension and e.active and (e.extension or "") == payload.extension:
            raise HTTPException(409, detail=f"La extensión {payload.extension} ya la usa {e.name}")
        if not code and not mail and _norm(e.name).lower() == name.lower():
            raise HTTPException(409, detail=f"Ya existe un empleado llamado '{e.name}'. Si es otra persona, agrega código o correo.")
    return name


@router.post("/employees", response_model=EmployeeRead, status_code=201)
def crear_empleado(payload: EmployeeCreate, session: Session = Depends(get_session)):
    name = _check_employee(session, payload)
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
    name = _check_employee(session, payload, emp_id)
    if emp.active and not payload.active:
        n = len(_assigned(session, emp_id))
        if n:
            raise HTTPException(400, detail=f"Tiene {n} equipo(s) asignado(s). Usa 'Dar de baja' o devuélvelos primero.")
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


# ------------------------------------------------------------------ ficha de empleado
def _emp_or_404(session: Session, emp_id: int) -> Employee:
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    return emp


def _assigned(session: Session, emp_id: int) -> list[ItAsset]:
    return list(session.exec(
        select(ItAsset).where(ItAsset.employee_id == emp_id, ItAsset.deleted_at.is_(None)).order_by(ItAsset.asset_tag)
    ).all())


def _emp_dict(e: Employee, count: int, paths: dict | None = None) -> dict:
    return {
        "id": e.id, "name": e.name, "email": e.email, "department": e.department, "active": e.active,
        "asset_count": count, "employee_code": e.employee_code, "position": e.position, "phone": e.phone,
        "extension": e.extension, "location_id": e.location_id, "notes": e.notes,
        "location": (paths or {}).get(e.location_id) if e.location_id else None,
    }


def _latin(s) -> str:
    return str(s).encode("latin-1", "replace").decode("latin-1")


# IMPORTANTE: /overview va antes que /{emp_id}
@router.get("/employees/export")
def empleados_export(session: Session = Depends(get_session)):
    import pandas as pd
    rows = empleados_overview(session)
    cols = ["Nombre", "Código", "Cargo", "Departamento", "Correo", "Teléfono", "Extensión", "Ubicación", "Activo", "Equipos"]
    df = pd.DataFrame([{
        "Nombre": r["name"], "Código": r["employee_code"], "Cargo": r["position"], "Departamento": r["department"],
        "Correo": r["email"], "Teléfono": r["phone"], "Extensión": r["extension"], "Ubicación": r["location"],
        "Activo": "Sí" if r["active"] else "No", "Equipos": r["asset_count"],
    } for r in rows], columns=cols)
    out = BytesIO()
    with pd.ExcelWriter(out, engine="openpyxl") as w:
        df.to_excel(w, index=False, sheet_name="Empleados")
    out.seek(0)
    return StreamingResponse(
        out, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=empleados.xlsx"},
    )


@router.get("/employees/overview")
def empleados_overview(session: Session = Depends(get_session)):
    counts: dict[int, int] = {}
    for a in session.exec(select(ItAsset).where(
        ItAsset.employee_id.is_not(None), ItAsset.deleted_at.is_(None), ItAsset.is_draft == False  # noqa: E712
    )).all():
        counts[a.employee_id] = counts.get(a.employee_id, 0) + 1
    emps = session.exec(select(Employee).order_by(Employee.name)).all()
    paths = location_paths(session)
    return [_emp_dict(e, counts.get(e.id, 0), paths) for e in emps]


@router.get("/employees/{emp_id}")
def empleado(emp_id: int, session: Session = Depends(get_session)):
    e = _emp_or_404(session, emp_id)
    return _emp_dict(e, len([a for a in _assigned(session, emp_id) if not a.is_draft]), location_paths(session))


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
