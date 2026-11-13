from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from contacts import init_db as contacts_init_db
from contacts import router as contacts_router
from inventario import init_db as inventario_init_db
from inventario import router as inventario_router
from redes import init_db as redes_init_db
from redes import router as redes_router


app = FastAPI(
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
app.include_router(contacts_router, prefix="/api")
app.include_router(inventario_router, prefix="/api")
app.include_router(redes_router, prefix="/api")
