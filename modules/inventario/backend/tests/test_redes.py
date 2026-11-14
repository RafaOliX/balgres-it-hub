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


def test_ip_no_valida_se_guarda_sin_reservar(client, cat):
    assert make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "DHCP"}).status_code == 201
    fila = client.get(f"{RBASE}/ips").json()[0]
    assert fila["state"] == "invalida" and fila["asset_tag"] == "MON-001" and fila["ip"] == "DHCP"
    assert client.get(f"{RBASE}/segments").json() == []


def test_borrador_reserva_y_no_bloquea_el_autoguardado(client, cat):
    assert make_asset(client, "MON-001", cat, is_draft=True, specs={"IP": "10.0.0.9"}).status_code == 201
    fila = [x for x in client.get(f"{RBASE}/ips").json() if x["ip"] == "10.0.0.9"][0]
    assert fila["is_draft"] is True and fila["state"] == "registrada"
    # un segundo borrador con la misma IP se guarda sin reservar
    assert make_asset(client, "MON-002", cat, is_draft=True, specs={"IP": "10.0.0.9"}).status_code == 201
    # un activo final no puede tomar una IP reservada por un borrador
    r = make_asset(client, "MON-003", cat, serial_number="S3", specs={"IP": "10.0.0.9"})
    assert r.status_code == 409 and "MON-001" in r.json()["detail"]
    # al finalizar el segundo borrador, el 409 también aparece
    r = client.patch(f"{BASE}/MON-002", json={"is_draft": False, "serial_number": "S2"})
    assert r.status_code == 409


def test_duplicadas_lista_los_activos_con_la_misma_ip(client, cat):
    make_asset(client, "MON-001", cat, is_draft=True, specs={"IP": "10.0.0.9"})
    make_asset(client, "MON-002", cat, is_draft=True, specs={"ip": "10.0.0.9"})
    d = client.get(f"{RBASE}/duplicates").json()
    assert d[0]["ip"] == "10.0.0.9" and {a["tag"] for a in d[0]["activos"]} == {"MON-001", "MON-002"}


def test_detecta_variantes_y_muestra_activos_sin_ip(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1", specs={"Dirección IP": "192.0.60.10", "Dirección MAC": "AA:BB"})
    make_asset(client, "MON-002", cat, serial_number="S2", specs={"MAC": "AA:BB:CC"})
    filas = {x["asset_tag"]: x for x in client.get(f"{RBASE}/ips").json()}
    assert filas["MON-001"]["ip"] == "192.0.60.10" and filas["MON-001"]["mac"] == "AA:BB"
    assert filas["MON-002"]["state"] == "sin_ip"


def test_segmentos_24_y_nombre(client, cat):
    make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "192.0.60.10"})
    make_asset(client, "MON-002", cat, serial_number="S2", specs={"IP": "192.168.1.5"})
    segs = client.get(f"{RBASE}/segments").json()
    assert [s["cidr"] for s in segs] == ["192.0.60.0/24", "192.168.1.0/24"]
    assert segs[0]["usadas"] == 1 and segs[0]["libres"] == 253
    assert client.put(f"{RBASE}/segments", json={"cidr": "192.0.60.0/24", "name": "Comedor"}).status_code == 200
    assert client.get(f"{RBASE}/segments").json()[0]["name"] == "Comedor"
    assert client.put(f"{RBASE}/segments", json={"cidr": "192.0.0.0/22", "name": "X"}).status_code == 422


def test_check_en_vivo_y_sync(client, cat):
    assert client.get(f"{RBASE}/ips/check", params={"ip": "DHCP"}).json()["valida"] is False
    make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "10.0.0.5"})
    r = client.get(f"{RBASE}/ips/check", params={"ip": "10.0.0.5"}).json()
    assert r["libre"] is False and r["usada_por"] == "MON-001"
    r = client.get(f"{RBASE}/ips/check", params={"ip": "10.0.0.5", "asset_tag": "MON-001"}).json()
    assert r["libre"] is True
    s = client.post(f"{RBASE}/sync").json()
    assert s["registradas"] == 1 and s["conflictos"] == []


def test_ip_manual_se_vincula_al_activo(client, cat):
    r = client.post(f"{RBASE}/ips", json={"ip": "10.0.0.7", "label": "DVR despacho"})
    assert r.status_code == 201
    assert client.post(f"{RBASE}/ips", json={"ip": "10.0.0.7"}).status_code == 409
    assert make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "10.0.0.7"}).status_code == 201
    fila = client.get(f"{RBASE}/ips").json()[0]
    assert fila["asset_tag"] == "MON-001" and fila["label"] == "DVR despacho"
    assert client.get(f"{RBASE}/ips/check", params={"ip": "10.0.0.7"}).json()["libre"] is False



def test_pistas_de_sistema_y_tipo():
    from redes.router import _kind_hint, _os_hint
    assert _os_hint(128) == "Windows" and _os_hint(64) == "Linux / red" and _os_hint(None) is None
    assert _kind_hint([9100, 80]) == "Impresora" and _kind_hint([22, 80]) == "Router / equipo de red"
    assert _kind_hint([]) is None


def test_escaneo_registra_las_vivas_y_las_edita_a_manual(client, cat, monkeypatch):
    import redes.router as rr
    make_asset(client, "MON-001", cat, serial_number="S1", specs={"IP": "10.9.9.5"})

    async def fake(ips):
        out = {ip: None for ip in ips}
        out["10.9.9.5"] = {"ms": 1.5, "ttl": 128, "ports": [445], "dns": "pc-ana"}
        out["10.9.9.77"] = {"ms": 3.0, "ttl": 64, "ports": [9100], "dns": None}
        return out

    monkeypatch.setattr(rr, "_ping_many", fake)
    r = client.post(f"{RBASE}/scan", json={"cidr": "10.9.9.0/24", "register": True}).json()
    assert r["vivas"] == 2 and r["nuevas_registradas"] == 1 and r["vivas_sin_registrar"] == []

    filas = {x["ip"]: x for x in client.get(f"{RBASE}/ips").json()}
    activo = filas["10.9.9.5"]
    assert activo["is_up"] is True and activo["os_hint"] == "Windows" and activo["dns_name"] == "pc-ana"
    assert activo["first_seen"] is not None and activo["latency_ms"] == 1.5
    nueva = filas["10.9.9.77"]
    assert nueva["origin"] == "escaneo" and nueva["kind"] == "Impresora" and nueva["open_ports"] == [9100]

    r = client.put(f"{RBASE}/ips/{nueva['id']}", json={"ip": "10.9.9.77", "label": "Impresora RRHH"})
    assert r.status_code == 200
    assert [x for x in client.get(f"{RBASE}/ips").json() if x["ip"] == "10.9.9.77"][0]["origin"] == "manual"


def test_escaneo_sin_register_solo_informa(client, monkeypatch):
    import redes.router as rr

    async def fake(ips):
        out = {ip: None for ip in ips}
        out["10.9.9.77"] = {"ms": 3.0, "ttl": 64, "ports": [], "dns": None}
        return out

    monkeypatch.setattr(rr, "_ping_many", fake)
    r = client.post(f"{RBASE}/scan", json={"cidr": "10.9.9.0/24"}).json()
    assert r["vivas_sin_registrar"] == ["10.9.9.77"] and r["nuevas_registradas"] == 0
    assert client.get(f"{RBASE}/ips").json() == []
