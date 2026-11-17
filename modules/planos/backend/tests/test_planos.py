from pathlib import Path
import os

from conftest import BASE, png


def test_health(client):
    assert client.get(f"{BASE}/health").json()["module"] == "planos"


def test_subir_valida_tipo_y_tamano(client):
    f = lambda n, b, t: client.post(f"{BASE}/", data={"name": "X"}, files={"file": (n, b, t)})  # noqa: E731
    assert f("a.txt", b"hola", "text/plain").status_code == 415
    assert f("a.png", b"no soy png", "image/png").status_code == 415
    assert f("a.png", b"0" * (10 * 1024 * 1024 + 1), "image/png").status_code == 413
    r = f("a.png", png(80, 40), "image/png")
    assert r.status_code == 201 and (r.json()["width"], r.json()["height"]) == (80, 40)
    assert client.post(f"{BASE}/", data={"name": "  "}, files={"file": ("a.png", png(), "image/png")}).status_code == 422


def test_pines_crud_y_validacion(client, plano):
    url = f"{BASE}/{plano['id']}/pins"
    assert client.post(url, json={"x": 120, "y": 10}).status_code == 422
    assert client.post(url, json={"x": 10, "y": 10, "kind": "dron"}).status_code == 422
    r = client.post(url, json={"x": 10.5, "y": 20, "kind": "CAMARA", "label": " Entrada ", "asset_tag": " CAM-001 "})
    assert r.status_code == 201
    pin = r.json()
    assert pin["kind"] == "camara" and pin["label"] == "Entrada" and pin["asset_tag"] == "CAM-001"

    r = client.put(f"{url}/{pin['id']}", json={"x": 50, "y": 60, "kind": "nvr", "asset_tag": ""})
    assert r.status_code == 200 and r.json()["asset_tag"] is None and r.json()["x"] == 50

    det = client.get(f"{BASE}/{plano['id']}").json()
    assert len(det["pins"]) == 1 and det["pin_count"] == 1
    assert client.get(BASE + "/").json()[0]["pin_count"] == 1

    assert client.delete(f"{url}/{pin['id']}").status_code == 204
    assert client.delete(f"{url}/{pin['id']}").status_code == 404


def test_estado_en_linea_desde_redes(client, plano):
    from sqlmodel import Session
    from contacts.db import engine
    try:
        from redes.models import IpAddress
    except ImportError:
        return
    with Session(engine) as s:
        s.add(IpAddress(ip="10.0.0.5", asset_tag="CAM-001", is_up=True))
        s.commit()
    url = f"{BASE}/{plano['id']}/pins"
    client.post(url, json={"x": 1, "y": 1, "asset_tag": "CAM-001"})
    client.post(url, json={"x": 2, "y": 2, "asset_tag": "CAM-999"})
    pins = client.get(f"{BASE}/{plano['id']}").json()["pins"]
    assert (pins[0]["ip"], pins[0]["is_up"]) == ("10.0.0.5", True)
    assert (pins[1]["ip"], pins[1]["is_up"]) == (None, None)


def test_renombrar_y_borrar_elimina_pines_y_archivo(client, plano):
    assert client.put(f"{BASE}/{plano['id']}", json={"name": "Piso 2", "notes": ""}).json()["name"] == "Piso 2"
    client.post(f"{BASE}/{plano['id']}/pins", json={"x": 1, "y": 1})
    f = Path(os.environ["UPLOADS_DIR"]) / "planos" / plano["filename"]
    assert f.exists()
    assert client.delete(f"{BASE}/{plano['id']}").status_code == 204
    assert not f.exists()
    assert client.get(f"{BASE}/{plano['id']}").status_code == 404
    assert client.post(f"{BASE}/{plano['id']}/pins", json={"x": 1, "y": 1}).status_code == 404
