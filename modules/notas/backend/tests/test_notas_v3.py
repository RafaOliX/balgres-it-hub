from conftest import BASE

PNG = "data:image/png;base64,iVBORw0KGgo="


def test_historial_registra_versiones_y_restaura(client):
    n = client.post(f"{BASE}/", json={"title": "Rack", "body": "v1", "tags": ["redes"]}).json()
    nid = n["id"]
    client.put(f"{BASE}/{nid}", json={"title": "Rack", "body": "v2", "tags": ["redes"]})
    client.put(f"{BASE}/{nid}", json={"title": "Rack", "body": "v2", "tags": ["redes"]})   # sin cambios: no crea versión
    h = client.get(f"{BASE}/{nid}/historial").json()
    assert [x["action"] for x in h] == ["Editada", "Creada"] and "contenido" in h[0]["detail"]
    v1 = h[1]
    assert client.get(f"{BASE}/{nid}/historial/{v1['id']}").json()["body"] == "v1"
    r = client.post(f"{BASE}/{nid}/historial/{v1['id']}/restore")
    assert r.status_code == 200 and r.json()["body"] == "v1"
    assert client.get(f"{BASE}/{nid}/historial").json()[0]["action"] == "Restaurada"


def test_eventos_de_archivos_y_diagramas_no_se_restauran(client):
    nid = client.post(f"{BASE}/", json={"title": "N"}).json()["id"]
    client.post(f"{BASE}/{nid}/archivos", files=[("files", ("a.zip", b"PK", "application/zip"))])
    h = client.get(f"{BASE}/{nid}/historial").json()
    assert h[0]["action"] == "Adjuntó un archivo" and h[0]["has_snapshot"] is False
    assert client.post(f"{BASE}/{nid}/historial/{h[0]['id']}/restore").status_code == 400


def test_preview_de_diagrama_se_guarda_y_se_conserva(client):
    nid = client.post(f"{BASE}/", json={"title": "N"}).json()["id"]
    d = client.post(f"{BASE}/{nid}/diagramas", json={"xml": "<mxfile/>", "preview": PNG}).json()
    assert client.get(f"{BASE}/{nid}/diagramas").json()[0]["preview"] == PNG
    client.put(f"{BASE}/{nid}/diagramas/{d['id']}", json={"title": "T", "xml": "<mxfile>x</mxfile>"})
    assert client.get(f"{BASE}/{nid}/diagramas/{d['id']}").json()["preview"] == PNG
    r = client.post(f"{BASE}/{nid}/diagramas", json={"xml": "x", "preview": "javascript:alert(1)"}).json()
    assert r["preview"] is None


def test_etiquetas_unifican_mayusculas(client):
    client.post(f"{BASE}/", json={"title": "A", "tags": ["Redes"]})
    client.post(f"{BASE}/", json={"title": "B", "tags": ["redes"]})
    assert client.get(f"{BASE}/tags").json() == [{"tag": "Redes", "count": 2}]
