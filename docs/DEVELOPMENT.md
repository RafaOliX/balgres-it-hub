# Desarrollo

## Flujo de ramas
- Todo trabajo nuevo va a `develop`. `main` solo recibe merges de `develop` ya probados (`make promote`).
- Instancia de pruebas aparte (otro puerto, otra DB): ver [INSTANCIAS.md](INSTANCIAS.md).
- Commits: `[hub] [inventario] [contacts] [redes] [auth] [scripts] [docs] mensaje`.

## Opción A: no toco el frontend (la más simple)
Usa el stack normal con `make setup`/`make deploy`: Flutter se compila dentro de Docker.

## Opción B: desarrollo con recarga rápida
Requiere Flutter instalado en tu máquina.

    cd docker && docker compose up -d        # backend en :8000 (con --reload), DB, Caddy en :8080
    cd ../apps/shell
    flutter run -d chrome --dart-define=API_BASE=http://localhost:8000/api

Swagger: `http://localhost:8000/docs`. El stack de `docker-compose.yml` (dev) monta `apps/shell/build/web`;
si no has compilado el frontend esa carpeta no existe y `:8080` sale en blanco. Compílalo con
`cd apps/shell && flutter build web --release --dart-define=API_BASE=/api`.

## Tests
    make test                 # backend (pytest, SQLite temporal) + frontend (flutter test), en Docker

Los tests nunca tocan la base real. Nota: las migraciones de `db.py` solo corren en Postgres,
así que los tests no las cubren: prueba un `make deploy` en la instancia de pruebas antes de promover.

## Añadir un módulo nuevo
Aplica siempre este checklist.

Backend (`modules/<mod>/backend/<mod>/`): `__init__`, `models`, `schemas`, `router`, `hooks` y `pyproject.toml`.
- Montar el router en `apps/core-api/app/main.py` con `dependencies=[Depends(guard("<mod>"))]`.
  `guard` mapea método HTTP a permiso: GET=`<mod>.ver`, DELETE=`<mod>.eliminar`, el resto=`<mod>.editar`.
- Añadir el módulo a `MODULES` en `apps/core-api/app/auth.py` y a `DEFAULT_ROLES` si aplica.
- Importar el módulo antes de `create_all` (los `init_db()` en `main.py`).
- Dependencia en `apps/core-api/pyproject.toml`.

Frontend (`modules/<mod>/frontend/`): `lib/balgres_it_<mod>.dart`, `api.dart` (Dio con interceptor Bearer
leyendo `AuthSession.token`), `pubspec.yaml`. Acciones protegidas con `AuthSession.can("<mod>.<accion>")`.

Shell: ruta en `apps/shell/lib/core/router.dart` (y en `_guards`), entrada en `layout.dart` con su permiso,
path dependency en `apps/shell/pubspec.yaml`.

Infra: `COPY` del módulo en `docker/Dockerfile.backend`, `Dockerfile.web` y `Dockerfile.android`;
**tablas nuevas en `EXPECTED_TABLES` de `scripts/backup.sh` y `scripts/restore.sh`**.

## Reglas de código
- Errores de API: `HTTPException` con `detail` en español; en Flutter, `apiError()`.
- Migraciones manuales en `db.py` (sin Alembic). Solo añadir columnas/índices con `IF NOT EXISTS`;
  nunca borrar ni renombrar sin plan de datos.
- Dependencias nuevas: justificarlas.
