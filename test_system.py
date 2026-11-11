import requests
import json
import os
import sys

BASE_URL = "http://localhost:8091/api/inventario"
AUTH = ("admin", os.environ["INV_PASS"])

def test_api():
    print("--- Iniciando Pruebas del Sistema ---")
    
    # 1. Probar Health
    r = requests.get(f"{BASE_URL}/health", auth=AUTH)
    assert r.status_code == 200, f"Error en Health: {r.status_code}"
    print("✅ Health Check OK")

    # 2. Probar Categorías
    r = requests.get(f"{BASE_URL}/categories", auth=AUTH)
    assert r.status_code == 200
    print(f"✅ Categorías OK ({len(r.json())} encontradas)")

    # 3. Crear un Activo (Borrador)
    payload = {
        "asset_tag": "TEST-999",
        "category": "Monitor",
        "brand": "Testing",
        "model": "Test Model",
        "serial_number": "TEST-SN-999",
        "is_draft": True
    }
    r = requests.post(f"{BASE_URL}/", json=payload, auth=AUTH)
    if r.status_code == 409:
        print("⚠️ El activo de prueba ya existe. Saltando creación.")
    else:
        assert r.status_code == 201, f"Error creando activo: {r.text}"
        print("✅ Creación de Activo OK")

    # 4. Actualizar el Activo (Quitar borrador)
    r = requests.patch(f"{BASE_URL}/TEST-999", json={"is_draft": False}, auth=AUTH)
    assert r.status_code == 200, f"Error actualizando: {r.text}"
    assert r.json()["is_draft"] == False
    print("✅ Actualización (Finalizar Borrador) OK")

    # 5. Descargar Excel
    r = requests.get(f"{BASE_URL}/export", auth=AUTH)
    assert r.status_code == 200
    assert "spreadsheetml" in r.headers.get("content-type", "")
    print("✅ Exportación Excel OK")

    # 6. Descargar PDF
    r = requests.get(f"{BASE_URL}/TEST-999/pdf", auth=AUTH)
    assert r.status_code == 200
    assert "pdf" in r.headers.get("content-type", "")
    print("✅ Generación PDF OK")

    # 7. Eliminar el Activo
    r = requests.delete(f"{BASE_URL}/TEST-999", auth=AUTH)
    assert r.status_code == 204
    r = requests.delete(f"{BASE_URL}/TEST-999/purge", auth=AUTH)
    assert r.status_code == 204
    print("✅ Eliminación (papelera + purga) OK")
    
    print("--- Todas las pruebas pasaron exitosamente ---")

if __name__ == "__main__":
    try:
        test_api()
    except Exception as e:
        print(f"❌ TEST FALLIDO: {e}")
        sys.exit(1)
