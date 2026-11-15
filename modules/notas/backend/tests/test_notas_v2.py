from conftest import BASE


def test_varios_activos_y_filtro(client):
    r = client.post(f"{BASE}/", json={"title": "Rack", "asset_tags": ["NVR-001", " SW-001 ", "nvr-001"]})
    assert r.status_code == 201 and r.json()["asset_tags"] == ["NVR-001", "SW-001"]
    nid = r.json()["id"]
    client.post(f"{BASE}/", json={"title": "Otra", "asset_tags": ["PC-001"]})
    assert [x["title"] for x in client.get(f"{BASE}/", params={"asset_tag": "SW-001"}).json()] == ["Rack"]
    assert [x["title"] for x in client.get(f"{BASE}/", params={"q": "pc-001"}).json()] == ["Otra"]

    r = client.put(f"{BASE}/{nid}", json={"title": "Rack", "asset_tags": ["SW-001", "UPS-001"]})
    assert r.json()["asset_tags"] == ["SW-001", "UPS-001"]
    assert client.get(f"{BASE}/{nid}").json()["asset_tags"] == ["SW-001", "UPS-001"]
    assert client.get(f"{BASE}/", params={"asset_tag": "NVR-001"}).json() == []


def test_asset_tag_legado_se_fusiona(client):
    r = client.post(f"{BASE}/", json={"title": "Vieja", "asset_tag": "NVR-001", "asset_tags": ["SW-001"]})
    assert r.json()["asset_tags"] == ["NVR-001", "SW-001"] and r.json()["asset_tag"] == "NVR-001"


def test_diagramas_crud(client):
    nid = client.post(f"{BASE}/", json={"title": "Red"}).json()["id"]
    assert client.post(f"{BASE}/999/diagramas", json={"xml": "<mxfile/>"}).status_code == 404
    d = client.post(f"{BASE}/{nid}/diagramas", json={"title": "Topología", "xml": "<mxfile/>"})
    assert d.status_code == 201
    did = d.json()["id"]
    assert [x["title"] for x in client.get(f"{BASE}/{nid}/diagramas").json()] == ["Topología"]
    assert client.get(f"{BASE}/", params={"q": "red"}).json()[0]["diagram_count"] == 1
    r = client.put(f"{BASE}/{nid}/diagramas/{did}", json={"title": "Topología v2", "xml": "<mxfile>x</mxfile>"})
    assert r.status_code == 200
    got = client.get(f"{BASE}/{nid}/diagramas/{did}").json()
    assert got["title"] == "Topología v2" and got["xml"] == "<mxfile>x</mxfile>"
    assert client.delete(f"{BASE}/{nid}/diagramas/{did}").status_code == 204
    assert client.get(f"{BASE}/{nid}/diagramas/{did}").status_code == 404


def test_borrar_nota_borra_diagramas_y_vinculos(client):
    nid = client.post(f"{BASE}/", json={"title": "N", "asset_tags": ["A-1"]}).json()["id"]
    client.post(f"{BASE}/{nid}/diagramas", json={"xml": "<mxfile/>"})
    assert client.delete(f"{BASE}/{nid}").status_code == 204
    assert client.get(f"{BASE}/{nid}/diagramas").status_code == 404
