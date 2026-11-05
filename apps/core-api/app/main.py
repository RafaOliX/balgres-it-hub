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
    allow_origins=["*"],   # en prod, restringir al dominio real
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "core-api"}

# Inicialización de módulos (crea tablas en DB)
inventario_init_db()

# Registro de routers de módulos
app.include_router(inventario_router, prefix="/api")
