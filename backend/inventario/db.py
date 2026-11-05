"""Engine y sesión de base de datos del módulo inventario."""
import os
from collections.abc import Iterator

from sqlmodel import Session, create_engine

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "sqlite:///./inventario.db",   # fallback dev fuera de Docker
)

engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session
