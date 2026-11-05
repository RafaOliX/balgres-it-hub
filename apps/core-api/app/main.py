from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from inventario import init_db as inventario_init_db
from inventario import router as inventario_router

app = FastAPI(
    title="Balgres IT Hub API",
    version="0.2.0",
    description="API central del departamento de IT",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

inventario_init_db()
app.include_router(inventario_router, prefix="/api")
