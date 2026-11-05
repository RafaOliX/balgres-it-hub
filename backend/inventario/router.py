from fastapi import APIRouter

router = APIRouter(prefix="/inventario", tags=["inventario"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"module": "inventario", "status": "ok"}
