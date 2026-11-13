"""Los tests usan SQLite temporal: NUNCA tocan la base real."""
import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="inv-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"   # forzado, no setdefault
os.environ["UPLOADS_DIR"] = f"{_TMP}/uploads"

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import SQLModel  # noqa: E402

from contacts import router as contacts_router  # noqa: E402
from inventario import router  # noqa: E402
from inventario.db import engine  # noqa: E402

assert engine.dialect.name == "sqlite", "los tests deben correr contra SQLite"

BASE = "/api/inventario"
CBASE = "/api/contacts"


@pytest.fixture(autouse=True)
def _fresh_db():
    SQLModel.metadata.drop_all(engine)
    SQLModel.metadata.create_all(engine)
    yield


@pytest.fixture()
def client():
    app = FastAPI()
    app.include_router(router, prefix="/api")
    app.include_router(contacts_router, prefix="/api")
    return TestClient(app)


@pytest.fixture()
def cat(client):
    r = client.post(f"{BASE}/categories", json={"name": "Monitor", "prefix": "MON", "requires_sn": True})
    assert r.status_code == 201
    return r.json()


@pytest.fixture()
def cat_free(client):
    r = client.post(f"{BASE}/categories", json={"name": "Cable", "prefix": "CBL", "requires_sn": False, "unit": "Metro"})
    assert r.status_code == 201
    return r.json()


def make_asset(client, tag, category, **kw):
    body = {"asset_tag": tag, "category": category["name"], "category_id": category["id"],
            "brand": "Dell", "model": "P2419H", **kw}
    return client.post(f"{BASE}/", json=body)
