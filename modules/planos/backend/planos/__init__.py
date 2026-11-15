"""Módulo de planos: imágenes con pines (cámaras, switches, APs, racks) vinculados a activos."""
from .router import init_db, router

__all__ = ["router", "init_db"]
