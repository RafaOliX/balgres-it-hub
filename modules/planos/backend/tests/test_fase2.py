import pytest
from sqlmodel import Session, select

from conftest import BASE
from contacts.db import engine


def _tz(**kw):
    return {"kind": "libre", "color": "#ff0000", "width": 4, "points": [[1, 1], [2, 2], [3, 3]], **kw}


def test_trazos_crud_y_validacion(client, plano):
    url = f"{BASE}/{plano['id']}/trazos"
    assert client.post(url, json=_tz(points=[[1, 1]])).status_code == 422               # libre: 2+ puntos
    assert client.post(url, json=_tz(kind="flecha")).status_code == 422                  # flecha: exactamente 2
    assert client.post(url, json=_tz(points=[[1, 1], [101, 2]])).status_code == 422      # fuera del plano
    assert client.post(url, json=_tz(color="rojo")).status_code == 422
    assert client.post(url, json=_tz(kind="circulo")).status_code == 422
    assert client.post(f"{BASE}/999/trazos", json=_tz()).status_code == 404

    r = client.post(url, json=_tz(kind="flecha", points=[[10, 10], [50, 50]]))
    assert r.status_code == 201 and r.json()["color"] == "#FF0000"
    t = r.json()
    det = client.get(f"{BASE}/{plano['id']}").json()
    assert [x["id"] for x in det["trazos"]] == [t["id"]] and det["trazos"][0]["points"] == [[10, 10], [50, 50]]
    assert client.delete(f"{url}/{t['id']}").status_code == 204
    assert client.delete(f"{url}/{t['id']}").status_code == 404


def test_limpiar_y_borrar_plano_elimina_trazos(client, plano):
    url = f"{BASE}/{plano['id']}/trazos"
    for _ in range(3):
        assert client.post(url, json=_tz()).status_code == 201
    assert client.delete(url).status_code == 204
    assert client.get(f"{BASE}/{plano['id']}").json()["trazos"] == []

    client.post(url, json=_tz())
    assert client.delete(f"{BASE}/{plano['id']}").status_code == 204
    from planos.models import PlanoTrazo
    with Session(engine) as s:
        assert s.exec(select(PlanoTrazo)).all() == []


def _nota(title="Doc cámaras") -> int:
    from notas.models import Nota
    with Session(engine) as s:
        n = Nota(title=title)
        s.add(n)
        s.commit()
        s.refresh(n)
        return n.id


def test_vinculo_con_notas(client, plano):
    pytest.importorskip("notas")
    nid = _nota()
    pins = f"{BASE}/{plano['id']}/pins"
    assert client.post(pins, json={"x": 1, "y": 1, "nota_id": 9999}).status_code == 404
    assert client.put(f"{BASE}/{plano['id']}", json={"name": "P", "nota_id": 9999}).status_code == 404

    pin = client.post(pins, json={"x": 1, "y": 1, "label": "NVR", "nota_id": nid}).json()
    assert pin["nota_id"] == nid
    assert client.put(f"{BASE}/{plano['id']}", json={"name": "Piso 1", "nota_id": nid}).status_code == 200

    det = client.get(f"{BASE}/{plano['id']}").json()
    assert det["nota_id"] == nid and det["nota_title"] == "Doc cámaras"
    assert det["pins"][0]["nota_title"] == "Doc cámaras"

    assert client.get(f"{BASE}/by-nota/{nid}").json() == [{"id": plano["id"], "name": "Piso 1", "plano": True, "pins": ["NVR"]}]
    assert client.get(f"{BASE}/by-nota/12345").json() == []
