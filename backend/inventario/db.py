"""Engine, sesión y migraciones simples del módulo inventario (Postgres)."""
import json
import os
from collections.abc import Iterator

from sqlalchemy import text
from sqlmodel import Session, create_engine

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./inventario.db")
engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)

DEFAULT_SPECS = {
    "Computadora": ["CPU", "RAM", "Disco", "SO", "Hostname", "IP", "MAC"],
    "Impresora": ["IP", "MAC", "Contador de páginas"],
    "Monitor": ["Pulgadas", "Resolución"],
}


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


def apply_migrations() -> None:
    if engine.dialect.name != "postgresql":
        return  # SQLite: create_all ya crea el esquema completo en una BD nueva

    with engine.begin() as conn:
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
        if conn.execute(text("SELECT COUNT(*) FROM categories")).scalar() == 0:
            conn.execute(text("""
                INSERT INTO categories (name, prefix, unit, requires_sn) VALUES
                ('Monitor', 'MON', 'Unidad', TRUE),
                ('Computadora', 'PC', 'Unidad', TRUE),
                ('Cable UTP', 'UTP', 'Metro', FALSE),
                ('Cable VGA', 'VGA', 'Unidad', FALSE),
                ('Impresora', 'PRN', 'Unidad', TRUE);
            """))

        # categorías
        conn.execute(text("ALTER TABLE categories ADD COLUMN IF NOT EXISTS spec_fields JSONB;"))
        for name, fields in DEFAULT_SPECS.items():
            conn.execute(
                text("UPDATE categories SET spec_fields = CAST(:v AS JSONB) WHERE name = :n AND spec_fields IS NULL"),
                {"v": json.dumps(fields), "n": name},
            )

        # activos (columnas históricas)
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES categories(id);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS unit VARCHAR(32) DEFAULT 'Unidad';"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS assigned_to VARCHAR(128);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS is_draft BOOLEAN DEFAULT FALSE;"))

        # activos (Fase 2). locations y employees ya existen: create_all corre antes.
        conn.execute(text("ALTER TABLE it_assets ALTER COLUMN location TYPE VARCHAR(256);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS location_id INTEGER REFERENCES locations(id);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS employee_id INTEGER REFERENCES employees(id);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS purchase_date DATE;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS cost DOUBLE PRECISION;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS supplier VARCHAR(128);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(64);"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS warranty_until DATE;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS specs JSONB;"))
        conn.execute(text("ALTER TABLE it_assets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_it_assets_deleted_at ON it_assets(deleted_at);"))
        conn.execute(text("ALTER TABLE it_assets DROP CONSTRAINT IF EXISTS it_assets_serial_number_key;"))

    # Cascada en imágenes (transacción aparte: si falla no contamina las demás)
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE it_asset_images DROP CONSTRAINT IF EXISTS it_asset_images_asset_id_fkey;"))
            conn.execute(text("ALTER TABLE it_asset_images ADD CONSTRAINT it_asset_images_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES it_assets(id) ON DELETE CASCADE;"))
    except Exception:
        pass
