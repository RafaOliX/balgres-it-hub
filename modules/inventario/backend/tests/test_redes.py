from conftest import BASE, RBASE, make_asset


def _ips(client):
    return [x["ip"] for x in client.get(f"{RBASE}/ips").json()]


def test_ip_unica_entre_activos_y_se_libera(client, cat):
    assert make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "10.0.0.5"}).status_code == 201
    r = make_asset(client, "MON-002", cat, serial_number="S2", specs={"ip": "10.0.0.5"})
    assert r.status_code == 409 and "10.0.0.5" in r.json()["detail"]
    assert client.get(f"{RBASE}/ips").json()[0]["asset_tag"] == "MON-001"

    client.patch(f"{BASE}/MON-001", json={"specs": {"IP": "10.0.0.6"}})
    assert _ips(client) == ["10.0.0.6"]

    client.delete(f"{BASE}/MON-001")
    assert _ips(client) == []


def test_ip_invalida_422_y_borrador_no_reserva(client, cat):
    assert make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "DHCP"}).status_code == 422
    assert make_asset(client, "MON-002", cat, is_draft=True, specs={"IP": "10.0.0.9"}).status_code == 201
    assert _ips(client) == []


def test_ip_manual_se_vincula_al_activo(client, cat):
    r = client.post(f"{RBASE}/ips", json={"ip": "10.0.0.7", "label": "DVR despacho"})
    assert r.status_code == 201
    assert client.post(f"{RBASE}/ips", json={"ip": "10.0.0.7"}).status_code == 409
    assert make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "10.0.0.7"}).status_code == 201
    fila = client.get(f"{RBASE}/ips").json()[0]
    assert fila["asset_tag"] == "MON-001" and fila["label"] == "DVR despacho"
    assert client.get(f"{RBASE}/ips/check", params={"ip": "10.0.0.7"}).json()["libre"] is False
