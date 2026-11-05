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

    Idempotente. Migra `image_path` (columna vieja) a la tabla nueva
    `it_asset_images`.
    """
    with engine.begin() as conn:
        # ¿existe la columna vieja image_path?
        result = conn.execute(text("""
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'it_assets' AND column_name = 'image_path'
        """))
        if result.first() is None:
            return

        # Copiar valores no nulos que aún no estén en la tabla nueva
        conn.execute(text("""
            INSERT INTO it_asset_images (asset_id, filename, created_at)
            SELECT a.id, a.image_path, NOW()
            FROM it_assets a
            WHERE a.image_path IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM it_asset_images i WHERE i.filename = a.image_path
              )
        """))
