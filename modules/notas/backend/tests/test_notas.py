from conftest import BASE


def _mk(client, **kw):
    body = {"title": "Nota", "body": "", "tags": [], **kw}
    return client.post(f"{BASE}/", json=body)


def test_health(client):
    assert client.get(f"{BASE}/health").json()["module"] == "notas"


def test_crud_basico_y_limpieza(client):
    r = _mk(client, title="  Cámaras   piso 2 ", body="NVR en rack 1", tags=["Cámaras", "cámaras", "rack", " "], asset_tag="  NVR-001 ")
    assert r.status_code == 201
    n = r.json()
    assert n["title"] == "Cámaras piso 2" and n["tags"] == ["Cámaras", "rack"] and n["asset_tag"] == "NVR-001"
    assert n["created_by"] == "admin"

    r = client.put(f"{BASE}/{n['id']}", json={"title": "Cámaras P2", "body": "nuevo", "tags": [], "asset_tag": ""})
    assert r.status_code == 200 and r.json()["asset_tag"] is None and r.json()["body"] == "nuevo"

    assert client.delete(f"{BASE}/{n['id']}").status_code == 204
    assert client.get(f"{BASE}/{n['id']}").status_code == 404


def test_titulo_vacio_422(client):
    assert _mk(client, title="   ").status_code == 422


def test_buscar_y_filtrar_por_etiqueta(client):
    _mk(client, title="Router sala", body="clave en bóveda", tags=["redes"])
    _mk(client, title="Cámaras", body="DVR bodega", tags=["cctv", "redes"])
    assert [x["title"] for x in client.get(f"{BASE}/", params={"q": "dvr"}).json()] == ["Cámaras"]
    assert len(client.get(f"{BASE}/", params={"tag": "REDES"}).json()) == 2
    assert [x["title"] for x in client.get(f"{BASE}/", params={"tag": "cctv"}).json()] == ["Cámaras"]


def test_etiquetas_con_conteo(client):
    _mk(client, tags=["redes", "cctv"])
    _mk(client, tags=["redes"])
    assert client.get(f"{BASE}/tags").json()[0] == {"tag": "redes", "count": 2}


def test_filtrar_por_activo(client):
    _mk(client, title="A", asset_tag="MON-001")
    _mk(client, title="B")
    assert [x["title"] for x in client.get(f"{BASE}/", params={"asset_tag": "MON-001"}).json()] == ["A"]
