"""Los tests usan SQLite temporal: NUNCA tocan la base real."""
import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="tickets-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"   # forzado, no setdefault
os.environ["UPLOADS_DIR"] = f"{_TMP}/uploads"

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import SQLModel  # noqa: E402

from contacts.db import engine  # noqa: E402
from tickets import router  # noqa: E402

assert engine.dialect.name == "sqlite", "los tests deben correr contra SQLite"

BASE = "/api/tickets"


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


def mk(client, **kw):
    return client.post(f"{BASE}/", json={"title": "Sin internet", **kw})
