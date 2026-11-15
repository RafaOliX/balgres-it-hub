import asyncio
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi import Depends, FastAPI
from contacts.common import current_user

from .auth import admin_router, auth_router, auth_username, guard, init_auth
from contacts import init_db as contacts_init_db
from contacts import router as contacts_router
from inventario import init_db as inventario_init_db
from inventario import router as inventario_router
from redes import init_db as redes_init_db
from redes import router as redes_router
from redes.router import periodic_ping
from notas import init_db as notas_init_db
from notas import router as notas_router
from planos import init_db as planos_init_db
from planos import router as planos_router


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = None
    try:
        minutes = int(os.getenv("REDES_PING_MINUTES", "5") or 0)
    except ValueError:
        minutes = 5
    if minutes > 0:
        task = asyncio.create_task(periodic_ping(minutes))
    yield
    if task:
        task.cancel()


app = FastAPI(
    lifespan=lifespan,
    title="Balgres IT Hub API",
    version="0.2.0",
    description="API central del departamento de IT",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(GZipMiddleware, minimum_size=1000)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "core-api"}

# Endpoint para la app Android
@app.get("/app/version")
async def app_version():
    return {
        "version": "1.0.0",
        "min_version": "1.0.0",
        "apk_url": "/apk/app-release.apk" # Ruta relativa servida por Caddy
    }

contacts_init_db()
inventario_init_db()
redes_init_db()
notas_init_db()
planos_init_db()
init_auth()

# El historial y la custodia registran al usuario autenticado, no "admin".
app.dependency_overrides[current_user] = auth_username

app.include_router(auth_router, prefix="/api")
app.include_router(admin_router, prefix="/api")
app.include_router(contacts_router, prefix="/api", dependencies=[Depends(guard("contactos"))])
app.include_router(inventario_router, prefix="/api", dependencies=[Depends(guard("inventario"))])
app.include_router(redes_router, prefix="/api", dependencies=[Depends(guard("redes"))])
app.include_router(notas_router, prefix="/api", dependencies=[Depends(guard("notas"))])
app.include_router(planos_router, prefix="/api", dependencies=[Depends(guard("planos"))])