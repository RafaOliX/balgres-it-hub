"""Router FastAPI del módulo contacts (prefijo /api/contacts)."""
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlmodel import Session, SQLModel, select

from .common import location_paths
from .db import apply_migrations, engine, get_session
from .hooks import hooks
from .models import Employee
from .schemas import EmployeeCreate, EmployeeRead

router = APIRouter(prefix="/contacts", tags=["contacts"])


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    apply_migrations()


def _norm(s: str) -> str:
    return " ".join(s.split())


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "contacts", "status": "ok"}


def _emp_or_404(session: Session, emp_id: int) -> Employee:
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    return emp


def _emp_dict(e: Employee, count: int, paths: dict | None = None) -> dict:
    return {
        "id": e.id, "name": e.name, "email": e.email, "department": e.department, "active": e.active,
        "asset_count": count, "employee_code": e.employee_code, "position": e.position, "phone": e.phone,
        "extension": e.extension, "location_id": e.location_id, "notes": e.notes,
        "location": (paths or {}).get(e.location_id) if e.location_id else None,
    }


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


@router.get("/employees", response_model=list[EmployeeRead])
def listar_empleados(solo_activos: bool = False, session: Session = Depends(get_session)):
    stmt = select(Employee).order_by(Employee.name)
    if solo_activos:
        stmt = stmt.where(Employee.active == True)  # noqa: E712
    return list(session.exec(stmt).all())


@router.post("/employees", response_model=EmployeeRead, status_code=201)
def crear_empleado(payload: EmployeeCreate, session: Session = Depends(get_session)):
    name = _check_employee(session, payload)
    emp = Employee(**{**payload.model_dump(), "name": name})
    session.add(emp)
    session.commit()
    session.refresh(emp)
    return emp


# IMPORTANTE: /export y /overview van antes que /{emp_id}
@router.get("/employees/overview")
def empleados_overview(session: Session = Depends(get_session)):
    counts = hooks.asset_counts(session)
    emps = session.exec(select(Employee).order_by(Employee.name)).all()
    paths = location_paths(session)
    return [_emp_dict(e, counts.get(e.id, 0), paths) for e in emps]


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


@router.get("/employees/{emp_id}")
def empleado(emp_id: int, session: Session = Depends(get_session)):
    e = _emp_or_404(session, emp_id)
    n = hooks.asset_counts(session, emp_id).get(emp_id, 0)
    return _emp_dict(e, n, location_paths(session))


@router.put("/employees/{emp_id}", response_model=EmployeeRead)
def actualizar_empleado(emp_id: int, payload: EmployeeCreate, session: Session = Depends(get_session)):
    emp = _emp_or_404(session, emp_id)
    name = _check_employee(session, payload, emp_id)
    if emp.active and not payload.active:
        n = hooks.open_assets(session, emp_id)
        if n:
            raise HTTPException(400, detail=f"Tiene {n} equipo(s) asignado(s). Usa 'Dar de baja' o devuélvelos primero.")
    renombrado = emp.name != name
    for k, v in payload.model_dump().items():
        setattr(emp, k, v)
    emp.name = name
    session.add(emp)
    if renombrado:
        hooks.renamed(session, emp_id, name)
    session.commit()
    session.refresh(emp)
    return emp


@router.delete("/employees/{emp_id}", status_code=204)
def eliminar_empleado(emp_id: int, session: Session = Depends(get_session)):
    emp = _emp_or_404(session, emp_id)
    if hooks.has_history(session, emp_id):
        raise HTTPException(400, detail="Tiene historial de asignaciones. Márcalo como inactivo en vez de eliminarlo")
    session.delete(emp)
    session.commit()
