"""Módulo de tickets: solicitudes de soporte con responsable, activo, solicitante, comentarios y adjuntos."""
from .router import init_db, router

__all__ = ["router", "init_db"]
