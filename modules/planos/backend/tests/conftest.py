"""Los tests usan SQLite temporal: NUNCA tocan la base real."""
import io
import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="planos-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"   # forzado, no setdefault
os.environ["UPLOADS_DIR"] = f"{_TMP}/uploads"

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import SQLModel  # noqa: E402

from contacts.db import engine  # noqa: E402
from planos import router  # noqa: E402

try:  # para probar el estado en línea (la tabla ip_addresses la crea redes)
    import redes.models  # noqa: F401
except ImportError:
    pass

try:  # para probar el vínculo con notas
    import notas.models  # noqa: F401
except ImportError:
    pass

assert engine.dialect.name == "sqlite", "los tests deben correr contra SQLite"

BASE = "/api/planos"


def png(w: int = 40, h: int = 20) -> bytes:
    from PIL import Image
    b = io.BytesIO()
    Image.new("RGB", (w, h)).save(b, "PNG")
    return b.getvalue()


@pytest.fixture(autouse=True)
def _fresh_db():
    SQLModel.metadata.drop_all(engine)
    SQLModel.metadata.create_all(engine)
    yield


@pytest.fixture()
def client():
    app = FastAPI()
    app.include_router(router, prefix="/api")
    return TestClient(app)


@pytest.fixture()
def plano(client):
    r = client.post(f"{BASE}/", data={"name": "Piso 1"}, files={"file": ("p.png", png(), "image/png")})
    assert r.status_code == 201
    return r.json()
