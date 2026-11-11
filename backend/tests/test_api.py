import io

import pandas as pd
import pytest

from conftest import BASE, make_asset


# ------------------------------------------------------------------ básicos
def test_health(client):
    assert client.get(f"{BASE}/health").json()["status"] == "ok"


# ------------------------------------------------------------------ categorías
def test_prefijo_duplicado_409(client, cat):
    r = client.post(f"{BASE}/categories", json={"name": "Otro", "prefix": "mon"})
    assert r.status_code == 409


def test_renombrar_categoria_actualiza_activos(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    r = client.put(f"{BASE}/categories/{cat['id']}", json={"name": "Pantalla", "prefix": "MON", "requires_sn": True})
    assert r.status_code == 200
    assert client.get(f"{BASE}/MON-001").json()["category"] == "Pantalla"


def test_no_borrar_categoria_en_uso_ni_con_hijas(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    assert client.delete(f"{BASE}/categories/{cat['id']}").status_code == 400
    hija = client.post(f"{BASE}/categories", json={"name": "Curvo", "prefix": "CRV", "parent_id": cat["id"]}).json()
    assert client.delete(f"{BASE}/categories/{cat['id']}").status_code == 400
    assert client.delete(f"{BASE}/categories/{hija['id']}").status_code == 204


def test_siguiente_tag_es_numerico_no_alfabetico(client, cat):
    make_asset(client, "MON-009", cat, serial_number="A")
    make_asset(client, "MON-010", cat, serial_number="B")
    r = client.get(f"{BASE}/siguiente-tag", params={"category_id": cat["id"]})
    assert r.json()["tag"] == "MON-011"


# ------------------------------------------------------------------ activos
def test_sn_obligatorio_en_final_pero_no_en_borrador(client, cat):
    assert make_asset(client, "MON-001", cat).status_code == 422
    assert make_asset(client, "MON-001", cat, is_draft=True).status_code == 201


def test_finalizar_borrador_por_patch_exige_sn(client, cat):
    make_asset(client, "MON-001", cat, is_draft=True)
    assert client.patch(f"{BASE}/MON-001", json={"is_draft": False}).status_code == 422
    r = client.patch(f"{BASE}/MON-001", json={"is_draft": False, "serial_number": "S1"})
    assert r.status_code == 200 and r.json()["is_draft"] is False


def test_finalizar_borrador_por_post_tambien_exige_sn(client, cat):
    make_asset(client, "MON-001", cat, is_draft=True)
    assert make_asset(client, "MON-001", cat).status_code == 422
    r = make_asset(client, "MON-001", cat, serial_number="S1")
    assert r.status_code == 201 and r.json()["is_draft"] is False


def test_tag_duplicado_en_activo_final_409(client, cat_free):
    assert make_asset(client, "CBL-001", cat_free).status_code == 201
    assert make_asset(client, "CBL-001", cat_free).status_code == 409


def test_historial_solo_registra_cambios_de_finales(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    client.patch(f"{BASE}/MON-001", json={"status": "Retirado"})
    h = client.get(f"{BASE}/MON-001/history").json()
    assert any(x["field_name"] == "status" and x["new_value"] == "Retirado" for x in h)

    make_asset(client, "MON-002", cat, is_draft=True)
    client.patch(f"{BASE}/MON-002", json={"brand": "LG"})
    campos = {x["field_name"] for x in client.get(f"{BASE}/MON-002/history").json()}
    assert campos == {"registro"}


def test_stock_no_puede_quedar_negativo(client, cat_free):
    make_asset(client, "CBL-001", cat_free)
    assert client.post(f"{BASE}/CBL-001/adjust-stock", params={"amount": -2}).status_code == 400
    r = client.post(f"{BASE}/CBL-001/adjust-stock", params={"amount": 5})
    assert r.json()["quantity"] == 6


# ------------------------------------------------------------------ papelera
def test_papelera_restaurar_y_purgar(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    assert client.delete(f"{BASE}/MON-001/purge").status_code == 400  # primero a la papelera
    assert client.delete(f"{BASE}/MON-001").status_code == 204
    assert client.get(f"{BASE}/MON-001").status_code == 404
    assert [a["asset_tag"] for a in client.get(f"{BASE}/papelera").json()] == ["MON-001"]
    assert client.post(f"{BASE}/MON-001/restore").status_code == 200
    assert client.get(f"{BASE}/MON-001").status_code == 200
    client.delete(f"{BASE}/MON-001")
    assert client.delete(f"{BASE}/MON-001/purge").status_code == 204
    assert client.get(f"{BASE}/papelera").json() == []


def test_limpiar_borradores(client, cat):
    make_asset(client, "MON-001", cat, is_draft=True)
    make_asset(client, "MON-002", cat, serial_number="S2")
    r = client.delete(f"{BASE}/borradores", params={"dias": 0})
    assert r.json()["eliminados"] == 1
    assert client.get(f"{BASE}/MON-002").status_code == 200


# ------------------------------------------------------------------ asignaciones
def test_asignar_reasignar_y_devolver(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    ana = client.post(f"{BASE}/employees", json={"name": "Ana"}).json()
    luis = client.post(f"{BASE}/employees", json={"name": "Luis"}).json()

    r = client.post(f"{BASE}/MON-001/assign", json={"employee_id": ana["id"]})
    assert r.status_code == 200 and r.json()["assigned_to"] == "Ana"
    assert client.post(f"{BASE}/MON-001/assign", json={"employee_id": ana["id"]}).status_code == 400

    assert client.post(f"{BASE}/MON-001/assign", json={"employee_id": luis["id"]}).json()["assigned_to"] == "Luis"
    hist = client.get(f"{BASE}/MON-001/assignments").json()
    assert len(hist) == 2 and sum(1 for x in hist if x["returned_at"] is None) == 1

    r = client.post(f"{BASE}/MON-001/return", json={})
    assert r.json()["assigned_to"] is None
    assert all(x["returned_at"] for x in client.get(f"{BASE}/MON-001/assignments").json())


def test_no_asignar_a_empleado_inactivo(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    e = client.post(f"{BASE}/employees", json={"name": "Ana"}).json()
    client.put(f"{BASE}/employees/{e['id']}", json={"name": "Ana", "active": False})
    assert client.post(f"{BASE}/MON-001/assign", json={"employee_id": e["id"]}).status_code == 400


def test_empleado_con_historial_no_se_borra(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    e = client.post(f"{BASE}/employees", json={"name": "Ana"}).json()
    client.post(f"{BASE}/MON-001/assign", json={"employee_id": e["id"]})
    assert client.delete(f"{BASE}/employees/{e['id']}").status_code == 400


# ------------------------------------------------------------------ ubicaciones
def test_unificar_ubicaciones_de_texto_libre(client, cat_free):
    for i, loc in enumerate(["Sistemas", "sistemas ", "SISTEMAS"], start=1):
        assert make_asset(client, f"CBL-00{i}", cat_free, location=loc).status_code == 201
    r = client.post(f"{BASE}/locations/import-from-assets").json()
    assert r == {"ubicaciones_creadas": 1, "activos_vinculados": 3}
    assert len(client.get(f"{BASE}/locations").json()) == 1


# ------------------------------------------------------------------ imágenes
def test_imagenes_validan_tipo_y_tamano(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    url = f"{BASE}/MON-001/images"
    assert client.post(url, files=[("files", ("a.txt", b"hola", "text/plain"))]).status_code == 415
    grande = b"0" * (5 * 1024 * 1024 + 1)
    assert client.post(url, files=[("files", ("a.png", grande, "image/png"))]).status_code == 413
    assert client.post(url, files=[("files", ("a.png", b"\x89PNG\r\n", "image/png"))]).status_code == 201


# ------------------------------------------------------------------ excel
def _xlsx(rows):
    buf = io.BytesIO()
    pd.DataFrame(rows).to_excel(buf, index=False)
    return buf.getvalue()


def test_importar_excel_crea_omite_y_reporta_errores(client, cat):
    data = _xlsx([
        {"Tag": "MON-100", "Categoría": "Monitor", "Marca": "LG", "Modelo": "24", "S/N": "A1"},
        {"Tag": "MON-101", "Categoría": "Inexistente", "Marca": "LG", "Modelo": "24"},
        {"Tag": "", "Categoría": "Monitor", "Marca": "LG", "Modelo": "24"},
    ])
    mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    r = client.post(f"{BASE}/import", files={"file": ("import.xlsx", data, mime)}).json()
    assert r["creados"] == 1 and len(r["errores"]) == 2
    r2 = client.post(f"{BASE}/import", files={"file": ("import.xlsx", data, mime)}).json()
    assert r2["creados"] == 0 and r2["omitidos"] == 1


def test_importar_excel_sin_columnas_obligatorias(client):
    mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    r = client.post(f"{BASE}/import", files={"file": ("x.xlsx", _xlsx([{"Foo": 1}]), mime)})
    assert r.status_code == 400


# ------------------------------------------------------------------ dashboard
def test_dashboard_no_cuenta_borradores(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    make_asset(client, "MON-002", cat, is_draft=True)
    d = client.get(f"{BASE}/dashboard").json()
    assert d["total"] == 1 and d["borradores"] == 1


# ------------------------------------------------------------------ PDF
# Si alguno falla es un hallazgo real (versión de fpdf, fuentes, etc.): pásame el traceback.
def test_acta_pdf(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    r = client.get(f"{BASE}/MON-001/pdf")
    assert r.status_code == 200 and r.content.startswith(b"%PDF")


def test_etiquetas_pdf(client, cat):
    pytest.importorskip("segno")
    make_asset(client, "MON-001", cat, serial_number="S1")
    r = client.get(f"{BASE}/labels")
    assert r.status_code == 200 and r.content.startswith(b"%PDF")


def test_ficha_de_empleado(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1")
    e = client.post(f"{BASE}/employees", json={"name": "Ana"}).json()
    client.post(f"{BASE}/MON-001/assign", json={"employee_id": e["id"]})
    ov = client.get(f"{BASE}/employees/overview").json()
    assert ov[0]["asset_count"] == 1
    assert [a["asset_tag"] for a in client.get(f"{BASE}/employees/{e['id']}/assets").json()] == ["MON-001"]
    assert len(client.get(f"{BASE}/employees/{e['id']}/history").json()) == 1
    assert client.get(f"{BASE}/employees/{e['id']}/pdf").content.startswith(b"%PDF")
