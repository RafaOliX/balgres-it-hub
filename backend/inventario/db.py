"""Engine, sesión y migraciones simples del módulo inventario."""
import os
from collections.abc import Iterator

from sqlalchemy import text
from sqlmodel import Session, create_engine

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./inventario.db")
engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


def apply_migrations() -> None:
    """Migraciones para agregar ondelete cascade a la tabla de imágenes."""
    with engine.begin() as conn:
        # 1. Migrar image_path viejo si existe
        result = conn.execute(text("""
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'it_assets' AND column_name = 'image_path'
        """))
        if result.first() is not None:
            conn.execute(text("""
                INSERT INTO it_asset_images (asset_id, filename, created_at)
                SELECT a.id, a.image_path, NOW()
                FROM it_assets a
                WHERE a.image_path IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM it_asset_images i WHERE i.filename = a.image_path)
            """))

        # 2. Arreglar FK de imágenes si no tiene ondelete cascade (para que eliminar activo borre fotos)
        try:
            conn.execute(text("ALTER TABLE it_asset_images DROP CONSTRAINT it_asset_images_asset_id_fkey;"))
            conn.execute(text("ALTER TABLE it_asset_images ADD CONSTRAINT it_asset_images_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES it_assets(id) ON DELETE CASCADE;"))
        except Exception:
            pass # Ya existe con cascade o la tabla es nueva

        # 3. Crear tabla de historial si no existe (create_all no la crea si ya existen las otras)
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS it_asset_history (
                id SERIAL PRIMARY KEY,
                asset_id INTEGER NOT NULL REFERENCES it_assets(id) ON DELETE CASCADE,
                field_name VARCHAR(64) NOT NULL,
                old_value VARCHAR,
                new_value VARCHAR,
                changed_by VARCHAR(64) NOT NULL DEFAULT 'admin',
                changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            );
        """))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_it_asset_history_asset_id ON it_asset_history(asset_id);"))
