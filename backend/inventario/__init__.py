"""Módulo de inventario de activos de TI."""
from .router import init_db, router

__all__ = ["router", "init_db"]
