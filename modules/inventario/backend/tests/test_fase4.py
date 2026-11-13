import io

import pandas as pd

from conftest import BASE, CBASE, make_asset

XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def test_estado_invalido_422(client, cat):
    assert make_asset(client, "MON-001", cat, serial_number="S1", status="Roto").status_code == 422
    make_asset(client, "MON-002", cat, serial_number="S2")
    assert client.patch(f"{BASE}/MON-002", json={"status": "Roto"}).status_code == 422


def test_tag_y_responsable_no_se_editan_por_patch(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    r = client.patch(f"{BASE}/MON-001", json={"asset_tag": "XXX-1", "assigned_to": "Pedro"})
    assert r.status_code == 200
    assert r.json()["asset_tag"] == "MON-001" and r.json()["assigned_to"] is None


def test_auto_tag_asigna_consecutivos(client, cat):
    body = {"asset_tag": "X", "category": "Monitor", "category_id": cat["id"], "brand": "Dell", "model": "M", "is_draft": True}
    tags = [client.post(f"{BASE}/?auto_tag=true", json=body).json()["asset_tag"] for _ in range(3)]
    assert tags == ["MON-001", "MON-002", "MON-003"]


def test_version_cambia_con_los_datos(client, cat):
    v0 = client.get(f"{BASE}/version").json()["v"]
    make_asset(client, "MON-001", cat, serial_number="S1")
    v1 = client.get(f"{BASE}/version").json()["v"]
    client.patch(f"{BASE}/MON-001", json={"status": "Retirado"})
    v2 = client.get(f"{BASE}/version").json()["v"]
    assert len({v0, v1, v2}) == 3


def test_empleados_duplicados_y_formatos(client):
    post = lambda **kw: client.post(f"{CBASE}/employees", json=kw)  # noqa: E731
    assert post(name="Ana Pérez", employee_code="E1", extension="204").status_code == 201
    assert post(name="Ana Pérez").status_code == 409                       # homónimo sin dato que distinga
    assert post(name="Ana Pérez", employee_code="E2").status_code == 201   # homónimo distinguible
    assert post(name="Luis", employee_code="E1").status_code == 409
    assert post(name="Luis", extension="204").status_code == 409
    assert post(name="Luis", extension="abc").status_code == 422
    assert post(name="Luis", phone="12").status_code == 422


def test_no_inactivar_empleado_con_equipos(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    e = client.post(f"{CBASE}/employees", json={"name": "Ana"}).json()
    client.post(f"{BASE}/MON-001/assign", json={"employee_id": e["id"]})
    r = client.put(f"{CBASE}/employees/{e['id']}", json={"name": "Ana", "active": False})
    assert r.status_code == 400


def test_papelera_cierra_la_custodia(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    e = client.post(f"{CBASE}/employees", json={"name": "Ana"}).json()
    client.post(f"{BASE}/MON-001/assign", json={"employee_id": e["id"]})
    client.delete(f"{BASE}/MON-001")
    assert all(x["returned_at"] for x in client.get(f"{BASE}/MON-001/assignments").json())
    assert client.get(f"{CBASE}/employees/overview").json()[0]["asset_count"] == 0


def _xlsx(rows):
    b = io.BytesIO()
    pd.DataFrame(rows).to_excel(b, index=False)
    return b.getvalue()


def test_importar_vincula_catalogos_y_valida(client, cat):
    base = {"Categoría": "Monitor", "Marca": "LG", "Modelo": "24"}
    data = _xlsx([
        {**base, "Tag": "MON-200", "S/N": "A9", "Ubicación": "Sistemas", "Asignado a": "Ana", "Estado": "retirado"},
        {**base, "Tag": "MON-201", "S/N": "A8", "Estado": "Roto"},
        {**base, "Tag": "MON-202"},  # sin S/N
    ])
    r = client.post(f"{BASE}/import", files={"file": ("i.xlsx", data, XLSX)}).json()
    assert r["creados"] == 1 and len(r["errores"]) == 2
    a = client.get(f"{BASE}/MON-200").json()
    assert a["status"] == "Retirado" and a["location_id"] and a["employee_id"]
    assert len(client.get(f"{BASE}/MON-200/assignments").json()) == 1


def test_dashboard_agregado_en_sql(client, cat, cat_free):
    make_asset(client, "MON-001", cat, serial_number="S1")
    make_asset(client, "MON-002", cat, serial_number="S2", status="Retirado")
    make_asset(client, "CBL-001", cat_free, quantity=5)
    make_asset(client, "MON-003", cat, is_draft=True)
    d = client.get(f"{BASE}/dashboard").json()
    assert d["total"] == 3 and d["borradores"] == 1 and d["unidades_totales"] == 7
    assert d["por_estado"] == {"Operativo": 2, "Retirado": 1}
    assert d["por_categoria"]["Monitor"] == 2


def test_imagen_corrupta_415(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    r = client.post(f"{BASE}/MON-001/images", files=[("files", ("a.png", b"no soy png", "image/png"))])
    assert r.status_code == 415


def test_pdf_con_caracteres_unicode(client):
    e = client.post(f"{CBASE}/employees", json={"name": "Łukasz Ñandú €"}).json()
    r = client.get(f"{BASE}/employees/{e['id']}/pdf")
    assert r.status_code == 200 and r.content.startswith(b"%PDF")
