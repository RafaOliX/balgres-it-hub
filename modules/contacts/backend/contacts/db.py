"""Engine compartido, sesión y migraciones de las tablas de contacts."""
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
    if engine.dialect.name != "postgresql":
        return
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS employee_code VARCHAR(64);"))
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS position VARCHAR(128);"))
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS phone VARCHAR(40);"))
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS extension VARCHAR(20);"))
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS location_id INTEGER REFERENCES locations(id);"))
        conn.execute(text("ALTER TABLE employees ADD COLUMN IF NOT EXISTS notes TEXT;"))
