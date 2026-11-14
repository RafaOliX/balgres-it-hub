"""Módulo de contactos: empleados (base para proveedores y empresas)."""
from .router import init_db, router

__all__ = ["router", "init_db"]
