"""Engine, sesión y migraciones simples del módulo inventario."""
import os
from collections.abc import Iterator

from sqlalchemy import text
from sqlmodel import Session, create_engine

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "sqlite:///./inventario.db",
)

engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


def apply_migrations() -> None:
    """Migraciones incrementales simples (SQLModel no altera columnas).

    Cada bloque es idempotente: si la columna ya existe, no hace nada.
    Para producción futura, migrar a Alembic.
    """
    with engine.begin() as conn:
        # Añadir image_path si no existe (Postgres)
        conn.execute(text("""
            ALTER TABLE it_assets
            ADD COLUMN IF NOT EXISTS image_path VARCHAR(256);
        """))
