from datetime import date, timedelta

from conftest import BASE, mk


def test_health(client):
    assert client.get(f"{BASE}/health").json()["module"] == "tickets"


def test_crear_y_validar(client):
    r = mk(client, title="  PC   lenta ", priority="Alta", asset_tag=" PC-001 ", requester_id=3, requester_name="Ana")
    assert r.status_code == 201
    t = r.json()
    assert t["title"] == "PC lenta" and t["asset_tag"] == "PC-001" and t["status"] == "Abierto" and t["created_by"] == "admin"
    assert mk(client, status="Roto").status_code == 422
    assert mk(client, priority="Urgente").status_code == 422
    assert client.post(f"{BASE}/", json={"title": "  "}).status_code == 422


def test_cambios_generan_eventos_y_resolucion(client):
    t = mk(client).json()
    body = {"title": "Sin internet", "status": "En curso", "priority": "Alta", "assignee": "luis"}
    r = client.put(f"{BASE}/{t['id']}", json=body).json()
    textos = [c["body"] for c in r["comments"] if c["kind"] == "evento"]
    assert any("Estado: Abierto → En curso" in x for x in textos) and any("Responsable: — → luis" in x for x in textos)
    assert r["resolved_at"] is None
    r = client.put(f"{BASE}/{t['id']}", json={**body, "status": "Resuelto"}).json()
    assert r["resolved_at"] is not None
    r = client.put(f"{BASE}/{t['id']}", json={**body, "status": "En curso"}).json()
    assert r["resolved_at"] is None
    n = len(r["comments"])
    assert len(client.put(f"{BASE}/{t['id']}", json={**body, "status": "En curso"}).json()["comments"]) == n  # sin cambios, sin eventos


def test_filtros_busqueda_y_resumen(client):
    mk(client, title="Impresora atascada", priority="Crítica", assignee="luis", asset_tag="PRN-001")
    mk(client, title="Correo", due_date=(date.today() - timedelta(days=2)).isoformat())
    cerrado = mk(client, title="Viejo", status="Cerrado").json()
    assert len(client.get(f"{BASE}/", params={"abiertos": True}).json()) == 2
    assert [x["title"] for x in client.get(f"{BASE}/", params={"q": "prn-001"}).json()] == ["Impresora atascada"]
    assert [x["id"] for x in client.get(f"{BASE}/", params={"q": f"T-{cerrado['id']:04d}"}).json()] == [cerrado["id"]]
    assert [x["title"] for x in client.get(f"{BASE}/", params={"assignee": "_none", "abiertos": True}).json()] == ["Correo"]
    assert [x["title"] for x in client.get(f"{BASE}/", params={"mios": True}).json()] == []
    s = client.get(f"{BASE}/resumen").json()
    assert s["abiertos"] == 2 and s["criticos"] == 1 and s["vencidos"] == 1 and s["sin_asignar"] == 1
    assert [x["vencido"] for x in client.get(f"{BASE}/", params={"q": "correo"}).json()] == [True]


def test_comentarios(client):
    t = mk(client).json()
    c = client.post(f"{BASE}/{t['id']}/comentarios", json={"body": " Reinicié el router "}).json()
    assert c["body"] == "Reinicié el router"
    assert client.post(f"{BASE}/{t['id']}/comentarios", json={"body": "   "}).status_code == 422
    det = client.get(f"{BASE}/{t['id']}").json()
    assert det["comment_count"] == 1
    evento = [x for x in det["comments"] if x["kind"] == "evento"][0]
    assert client.delete(f"{BASE}/{t['id']}/comentarios/{evento['id']}").status_code == 400
    assert client.delete(f"{BASE}/{t['id']}/comentarios/{c['id']}").status_code == 204


def test_archivos_ciclo_y_limpieza(client, monkeypatch):
    import importlib
    import os
    from pathlib import Path
    t = mk(client).json()
    r = client.post(f"{BASE}/{t['id']}/archivos", files=[("files", ("../x/captura.png", b"\x89PNG", "image/png"))])
    assert r.status_code == 201 and r.json()[0]["original_name"] == "captura.png"
    aid = r.json()[0]["id"]
    d = client.get(f"{BASE}/{t['id']}/archivos/{aid}/download")
    assert d.status_code == 200 and d.content == b"\x89PNG"
    rr = importlib.import_module("tickets.router")
    monkeypatch.setattr(rr, "MAX_FILE_BYTES", 5)
    assert client.post(f"{BASE}/{t['id']}/archivos", files=[("files", ("a.bin", b"0" * 50, "application/octet-stream"))]).status_code == 413
    folder = Path(os.environ["UPLOADS_DIR"]) / "_private" / "tickets"
    assert len(list(folder.glob("*"))) == 1                       # el rechazado no deja basura
    assert client.delete(f"{BASE}/{t['id']}").status_code == 204
    assert not any(folder.glob("*"))
    assert client.get(f"{BASE}/{t['id']}").status_code == 404
