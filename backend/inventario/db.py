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
    with engine.begin() as conn:
        # Crear tabla categories si no existe (SQLModel no la crea si ya hay tablas)
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS categories (
                id SERIAL PRIMARY KEY,
                name VARCHAR(64) UNIQUE NOT NULL,
                parent_id INTEGER REFERENCES categories(id),
                prefix VARCHAR(10) NOT NULL,
                unit VARCHAR(32) NOT NULL DEFAULT 'Unidad',
                requires_sn BOOLEAN NOT NULL DEFAULT TRUE
            );
        """))
        
        # Insertar categorías por defecto si la tabla está vacía
        result = conn.execute(text("SELECT COUNT(*) FROM categories"))
        if result.scalar() == 0:
            conn.execute(text("""
                INSERT INTO categories (name, prefix, unit, requires_sn) VALUES 
                ('Monitor', 'MON', 'Unidad', TRUE),
                ('Computadora', 'PC', 'Unidad', TRUE),
                ('Cable UTP', 'UTP', 'Metro', FALSE),
                ('Cable VGA', 'VGA', 'Unidad', FALSE),
                ('Impresora', 'PRN', 'Unidad', TRUE);
            """))

        # Añadir columnas nuevas a it_assets
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES categories(id);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS unit VARCHAR(32) DEFAULT 'Unidad';"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS assigned_to VARCHAR(128);"))
        
        # Quitar constraints viejos
        try:
            conn.execute(text("ALTER TABLE it_assets DROP CONSTRAINT IF EXISTS it_assets_serial_number_key;"))
        except Exception:
            pass

        # Arreglar FK de imágenes
        try:
            conn.execute(text("ALTER TABLE it_asset_images DROP CONSTRAINT it_asset_images_asset_id_fkey;"))
            conn.execute(text("ALTER TABLE it_asset_images ADD CONSTRAINT it_asset_images_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES it_assets(id) ON DELETE CASCADE;"))
        except Exception:
            pass
