"""Plantillas personalizables de acta / hoja en blanco y generación de PDF."""
import os
from datetime import datetime
from io import BytesIO
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from fpdf import FPDF
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from .common import location_paths
from .db import engine, get_session
from .models import ActaTemplate, Employee, ItAsset

router = APIRouter()

EMP_FIELDS = {
    "name": "Nombre", "employee_code": "Código / ID", "position": "Cargo", "department": "Departamento",
    "email": "Correo", "phone": "Teléfono", "extension": "Extensión", "location": "Sede / ubicación",
}
ASSET_COLS = {
    "tag": ("Tag", 22), "equipo": ("Equipo", 55), "category": ("Categoría", 28), "brand": ("Marca", 24),
    "model": ("Modelo", 30), "serial": ("S/N", 34), "quantity": ("Cantidad", 20), "status": ("Estado", 22),
    "location": ("Ubicación", 36), "specs": ("Datos técnicos", 60), "notes": ("Notas", 45),
}

DEFAULT_CONFIG: dict[str, Any] = {
    "title": "Acta de Entrega de Equipos TI",
    "intro": "Por medio de la presente se hace entrega de los equipos detallados a continuación a {empleado}, "
             "quien los recibe en buen estado y se compromete a su cuidado y buen uso.",
    "employee_fields": ["name", "position", "department", "extension"],
    "asset_columns": ["tag", "equipo", "serial", "quantity"],
    "orientation": "P",
    "show_date": True,
    "blank_rows": 10,
    "signatures": ["Firma Responsable TI", "Firma de Recibido"],
    "footer": "",
}


def normalize_config(cfg: dict | None) -> dict:
    d = {**DEFAULT_CONFIG, **(cfg or {})}
    d["employee_fields"] = [k for k in (d.get("employee_fields") or []) if k in EMP_FIELDS]
    d["asset_columns"] = [k for k in (d.get("asset_columns") or []) if k in ASSET_COLS] or ["tag", "equipo", "serial", "quantity"]
    d["orientation"] = "L" if d.get("orientation") == "L" else "P"
    try:
        d["blank_rows"] = max(0, min(40, int(d.get("blank_rows") or 0)))
    except (TypeError, ValueError):
        d["blank_rows"] = 10
    d["signatures"] = [str(x).strip()[:60] for x in (d.get("signatures") or []) if str(x).strip()][:4]
    for k in ("title", "intro", "footer"):
        d[k] = str(d.get(k) or "")[:2000]
    d["show_date"] = bool(d.get("show_date"))
    return d


def seed_templates() -> None:
    with Session(engine) as s:
        if s.exec(select(ActaTemplate)).first():
            return
        s.add(ActaTemplate(name="Acta de entrega estándar", config=DEFAULT_CONFIG))
        s.add(ActaTemplate(name="Hoja en blanco (llenar a mano)", config={
            **DEFAULT_CONFIG, "title": "Hoja de entrega de equipos", "intro": "",
            "employee_fields": list(EMP_FIELDS.keys()), "asset_columns": ["tag", "equipo", "serial", "quantity", "notes"],
            "blank_rows": 10,
        }))
        s.commit()


# ------------------------------------------------------------------ render
_FONT_DIR = os.getenv("PDF_FONT_DIR", "/usr/share/fonts/truetype/dejavu")


def _latin(s) -> str:
    return str(s).encode("latin-1", "replace").decode("latin-1")


class _Doc:
    """Envuelve FPDF: fuente Unicode si existe (DejaVu) y, si no, Helvetica con latin-1."""

    def __init__(self, landscape: bool):
        self.pdf = FPDF(orientation="L" if landscape else "P", unit="mm", format="A4")
        reg, bold = os.path.join(_FONT_DIR, "DejaVuSans.ttf"), os.path.join(_FONT_DIR, "DejaVuSans-Bold.ttf")
        self.uni = os.path.exists(reg) and os.path.exists(bold)
        if self.uni:
            self.pdf.add_font("DJ", "", reg)
            self.pdf.add_font("DJ", "B", bold)
            self.pdf.add_font("DJ", "I", reg)
        self.pdf.set_auto_page_break(True, margin=15)
        self.pdf.add_page()

    def font(self, size: float, style: str = "") -> None:
        self.pdf.set_font("DJ" if self.uni else "Helvetica", style, size)

    def t(self, s) -> str:
        return str(s) if self.uni else _latin(s)

    def fit(self, text, w: float) -> str:
        text = self.t(text)
        if self.pdf.get_string_width(text) <= w - 2:
            return text
        while text and self.pdf.get_string_width(text + ".") > w - 2:
            text = text[:-1]
        return text + "."

    def line(self, w, h, text, align="") -> None:
        self.pdf.cell(w, h, text=self.t(text), align=align, new_x="LMARGIN", new_y="NEXT")


def _emp_val(emp: Employee, key: str, paths: dict) -> str:
    if key == "location":
        return paths.get(emp.location_id, "") if emp.location_id else ""
    return str(getattr(emp, key, "") or "")


def _asset_val(a: ItAsset, key: str) -> str:
    return {
        "tag": a.asset_tag, "equipo": f"{a.category} {a.brand} {a.model}".strip(),
        "category": a.category, "brand": a.brand, "model": a.model, "serial": a.serial_number or "N/A",
        "quantity": f"{a.quantity} {a.unit or ''}".strip(), "status": a.status or "-", "location": a.location or "-",
        "specs": "; ".join(f"{k}: {v}" for k, v in (a.specs or {}).items()) or "-", "notes": a.notes or "-",
    }[key]


def render_acta(session: Session, cfg: dict | None, emp: Employee | None, assets: list[ItAsset], blank_table: bool = False) -> bytes:
    cfg = normalize_config(cfg)
    land = cfg["orientation"] == "L"
    W = 277 if land else 190
    paths = location_paths(session)
    blank_doc = blank_table or (emp is None and not assets)
    d = _Doc(land)
    pdf = d.pdf

    nombre = emp.name if emp else "____________________"
    fecha = "____ / ____ / ________" if blank_doc else f"{datetime.now():%d/%m/%Y}"

    def fmt(t: str) -> str:
        return t.replace("{empleado}", nombre).replace("{fecha}", fecha)

    d.font(16, "B")
    d.line(W, 10, fmt(cfg["title"]), align="C")
    if cfg["show_date"]:
        d.font(10)
        d.line(W, 7, f"Fecha: {fecha}", align="C")
    pdf.ln(4)

    if cfg["intro"].strip():
        d.font(11)
        pdf.multi_cell(W, 6, text=d.t(fmt(cfg["intro"])), new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

    fields = cfg["employee_fields"]
    if fields:
        d.font(11)
        half = W / 2
        for i, key in enumerate(fields):
            val = _emp_val(emp, key, paths) if emp else ""
            txt = d.fit(f"{EMP_FIELDS[key]}: {val if val else '_' * 26}", half)
            if i % 2 == 1 or i == len(fields) - 1:
                pdf.cell(half, 8, text=txt, new_x="LMARGIN", new_y="NEXT")
            else:
                pdf.cell(half, 8, text=txt)

    cols = cfg["asset_columns"]
    total = sum(ASSET_COLS[k][1] for k in cols)
    widths = [ASSET_COLS[k][1] * W / total for k in cols]
    pdf.ln(4)
    d.font(9, "B")
    pdf.set_fill_color(235, 238, 245)
    for k, w in zip(cols, widths):
        pdf.cell(w, 8, text=d.fit(ASSET_COLS[k][0], w), border=1, fill=True)
    pdf.ln(8)
    d.font(9)
    if assets:
        for a in assets:
            for k, w in zip(cols, widths):
                pdf.cell(w, 8, text=d.fit(_asset_val(a, k), w), border=1)
            pdf.ln(8)
    elif blank_table or emp is None:
        for _ in range(cfg["blank_rows"]):
            for w in widths:
                pdf.cell(w, 9, text="", border=1)
            pdf.ln(9)
    else:
        pdf.cell(W, 8, text="Sin equipos asignados", border=1, new_x="LMARGIN", new_y="NEXT")

    sigs = cfg["signatures"]
    if sigs:
        pdf.ln(28)
        w = W / len(sigs)
        d.font(11)
        for _ in sigs:
            pdf.cell(w, 8, text="_" * int(w / 2.4), align="C")
        pdf.ln(8)
        for s in sigs:
            pdf.cell(w, 6, text=d.fit(s, w), align="C")
        pdf.ln(6)

    if cfg["footer"].strip():
        pdf.ln(10)
        d.font(9, "I")
        pdf.multi_cell(W, 5, text=d.t(fmt(cfg["footer"])), new_x="LMARGIN", new_y="NEXT")

    return bytes(pdf.output())


def _pdf_response(data: bytes, filename: str) -> StreamingResponse:
    return StreamingResponse(BytesIO(data), media_type="application/pdf",
                             headers={"Content-Disposition": f"attachment; filename={filename}"})


# ------------------------------------------------------------------ API de plantillas
class ActaTemplateIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    config: dict[str, Any] = Field(default_factory=dict)


class ActaTemplateOut(BaseModel):
    id: int
    name: str
    config: dict[str, Any]


def _out(t: ActaTemplate) -> ActaTemplateOut:
    return ActaTemplateOut(id=t.id, name=t.name, config=normalize_config(t.config))


def _tpl_or_404(session: Session, tid: int) -> ActaTemplate:
    t = session.get(ActaTemplate, tid)
    if not t:
        raise HTTPException(404, detail="Plantilla no encontrada")
    return t


@router.get("/acta-templates", response_model=list[ActaTemplateOut])
def listar_plantillas(session: Session = Depends(get_session)):
    return [_out(t) for t in session.exec(select(ActaTemplate).order_by(ActaTemplate.name)).all()]


@router.post("/acta-templates", response_model=ActaTemplateOut, status_code=201)
def crear_plantilla(payload: ActaTemplateIn, session: Session = Depends(get_session)):
    t = ActaTemplate(name=payload.name.strip(), config=normalize_config(payload.config))
    session.add(t)
    session.commit()
    session.refresh(t)
    return _out(t)


@router.put("/acta-templates/{tid}", response_model=ActaTemplateOut)
def actualizar_plantilla(tid: int, payload: ActaTemplateIn, session: Session = Depends(get_session)):
    t = _tpl_or_404(session, tid)
    t.name = payload.name.strip()
    t.config = normalize_config(payload.config)
    session.add(t)
    session.commit()
    session.refresh(t)
    return _out(t)


@router.delete("/acta-templates/{tid}", status_code=204)
def eliminar_plantilla(tid: int, session: Session = Depends(get_session)):
    session.delete(_tpl_or_404(session, tid))
    session.commit()


@router.get("/acta-templates/{tid}/pdf")
def plantilla_pdf(tid: int, employee_id: int | None = None, tags: str | None = None, blank: bool = False,
                  session: Session = Depends(get_session)):
    """Sin parámetros: hoja en blanco. Con employee_id: datos del empleado. blank=true: tabla vacía."""
    t = _tpl_or_404(session, tid)
    emp = session.get(Employee, employee_id) if employee_id else None
    if employee_id and not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    assets: list[ItAsset] = []
    if tags:
        lista = [x.strip() for x in tags.split(",") if x.strip()]
        assets = list(session.exec(select(ItAsset).where(ItAsset.asset_tag.in_(lista), ItAsset.deleted_at.is_(None))).all())
    return _pdf_response(render_acta(session, t.config, emp, assets, blank_table=blank), f"plantilla_{t.id}.pdf")


@router.get("/employees/{emp_id}/pdf")
def empleado_acta(emp_id: int, template_id: int | None = None, session: Session = Depends(get_session)):
    emp = session.get(Employee, emp_id)
    if not emp:
        raise HTTPException(404, detail="Empleado no encontrado")
    cfg = _tpl_or_404(session, template_id).config if template_id is not None else DEFAULT_CONFIG
    assets = list(session.exec(
        select(ItAsset).where(ItAsset.employee_id == emp_id, ItAsset.deleted_at.is_(None), ItAsset.is_draft == False)  # noqa: E712
        .order_by(ItAsset.asset_tag)
    ).all())
    return _pdf_response(render_acta(session, cfg, emp, assets), f"acta_empleado_{emp.id}.pdf")
