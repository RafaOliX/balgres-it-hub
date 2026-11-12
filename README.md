# balgres-it-hub

Hub central de herramientas del departamento de IT de Balgres.

## Estructura
- `apps/core-api/` — Backend FastAPI (auth, DB, carga de módulos)
- `apps/shell/`    — App Flutter (Web + Android)
- `modules/`       — Submódulos (inventario, tickets, etc.)
- `docker/`        — Stack Docker Compose
- `scripts/`       — Scripts de bootstrap

## Clonar
    git clone --recurse-submodules git@github.com:RafaOliX/balgres-it-hub.git
# Balgres IT Hub

Plataforma modular de herramientas internas del departamento de IT de **Balgres**.
Hoy tiene un módulo: **Inventario**. Diseñada para crecer con tickets, licencias,
usuarios, etc.

---

## Stack

| Capa | Tecnología |
|---|---|
| Frontend | Flutter 3.47+ (Web + Android desde el mismo código) |
| Backend | FastAPI (Python 3.11) + SQLModel |
| Base de datos | PostgreSQL 16 |
| Proxy / estáticos | Caddy 2 (TLS automático, basic auth, SPA fallback) |
| Orquestación | Docker Compose (dev y prod) |
| Control de versiones | Git con submódulos (`hub` + `modules/*` independientes) |

---

## Arquitectura

```
┌────────────────────────────────────────────────┐
│  Flutter (Web/Android) — apps/shell            │
│  └── Módulos Flutter — modules/*/frontend      │
└────────────────────┬───────────────────────────┘
                     │ HTTP(S)
┌────────────────────▼───────────────────────────┐
│  Caddy — proxy /api → backend + /srv/web       │
│  Basic auth + SPA fallback + headers seguros   │
└────────────────────┬───────────────────────────┘
                     │
┌────────────────────▼───────────────────────────┐
│  FastAPI — apps/core-api (monta routers de     │
│  los módulos) + modules/*/backend (paquetes)   │
└────────────────────┬───────────────────────────┘
                     │
┌────────────────────▼───────────────────────────┐
│  PostgreSQL 16 (volumen persistente pgdata)    │
└────────────────────────────────────────────────┘
```

**Filosofía modular**: cada módulo es una rebanada full-stack independiente
(`frontend/` Flutter + `backend/` Python), versionada en su propio repo y
consumida por el hub como **submódulo git**. Añadir un módulo = añadir un
submódulo + registrar su router en `apps/core-api/app/main.py`.

---

## Estructura del repositorio

```
balgres-it-hub/
├── apps/
│   ├── core-api/            # FastAPI que monta los routers de los módulos
│   └── shell/               # App Flutter que aloja las pantallas de los módulos
├── modules/                 # Submódulos git (uno por app del depto)
│   └── inventario/          # → balgres-it-inventario (repo independiente)
│       ├── backend/         # Paquete Python (instalado editable)
│       ├── frontend/        # Paquete Flutter (consumido como path dependency)
│       └── legacy/          # CLI original en Python (referencia)
├── docker/
│   ├── docker-compose.yml       # Dev
│   ├── docker-compose.prod.yml  # Prod
│   ├── Caddyfile                # Dev (:8080)
│   ├── Caddyfile.prod           # Prod (:80, basic auth, env var para hash)
│   ├── Dockerfile.backend       # Backend Python
│   └── Dockerfile.web           # Multi-stage: compila Flutter + sirve con Caddy
├── scripts/
│   └── setup-server.sh      # Bootstrap completo de servidor (genera secretos, build, up)
├── deploy/
│   └── README.md            # Instrucciones concisas de deploy
├── .env.prod.example        # Plantilla de variables de entorno de producción
└── .dockerignore
```

---

## Requisitos

**Máquina de desarrollo**:
- Docker + Docker Compose v2
- Git
- Flutter 3.47+ (solo si compilas Web/Android en host — opcional, Docker lo hace)
- OpenSSL (para generar secretos)

**Servidor**:
- Linux (probado Ubuntu/Debian y compatible con RHEL)
- Docker + Docker Compose v2
- Git
- OpenSSL
- Puerto 80 libre (o adaptar `docker-compose.prod.yml`)

---

## Desarrollo local

### Levantar el stack

```bash
cd docker
cp ../.env.example ../.env       # opcional, dev funciona sin él
docker compose up -d
```

Servicios disponibles:

| URL | Qué |
|---|---|
| `http://localhost:8080/` | App Flutter Web (servida por Caddy) |
| `http://localhost:8080/api/*` | API a través de Caddy |
| `http://localhost:8000/docs` | Swagger interactivo (backend directo, sin auth) |
| `http://localhost:8000/healthz` | Health del backend |

> **Nota**: en desarrollo, Caddy usa el puerto **8080** para no chocar con
> otros servicios (Odoo, nginx, etc.) que suelen ocupar el `:80`. En producción
> usa el `:80`.

### Recompilar Flutter Web después de cambios

```bash
cd apps/shell
flutter build web --release --dart-define=API_BASE=/api
```

Caddy monta `apps/shell/build/web` como volumen: no hace falta reiniciar el
contenedor, solo recargar el navegador (**Ctrl+Shift+R** si cachea).

### Ciclo rápido de iteración (hot reload)

```bash
cd apps/shell
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000/api
```

Usa el backend directo por `:8000` (el CORS del backend ya permite `*`).
Ciclo de ~2s vs ~30s con build.

---

## Deploy en servidor

### Prerrequisitos (una vez por servidor)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt install -y git openssl
```

### Deploy completo

```bash
git clone --recurse-submodules git@github.com:RafaOliX/balgres-it-hub.git
cd balgres-it-hub
./scripts/setup-server.sh
```

El script:

1. Verifica Docker y que los submódulos estén clonados.
2. Genera `.env.prod` con `DB_PASSWORD` y `JWT_SECRET` aleatorios (OpenSSL).
3. **Pide interactivamente el password de `admin`** y lo guarda escapado
   para `basic_auth` de Caddy (ver "Troubleshooting → $ del hash bcrypt").
4. Verifica que el puerto 80 esté libre.
5. Compila imágenes (primera vez ~10 min por SDK de Flutter en Docker).
6. Levanta el stack.

Al final:

```
✔ Verifica: curl -u admin:TU_PASSWORD http://localhost/api/inventario/health
✔ Abre:     http://<IP-del-servidor>/
```

### Actualizar tras cambios

```bash
cd balgres-it-hub
git pull
git submodule update --remote --merge    # si cambió el submódulo
./scripts/setup-server.sh                # detecta cambios, no toca .env.prod
```

### Rollback

```bash
git log --oneline -10
git checkout <sha-anterior>
./scripts/setup-server.sh

# Los datos de Postgres viven en el volumen pgdata → sobreviven rollbacks.
# Solo se pierden con `docker compose down -v` (no usar en prod).
```

---

## Gestión de secretos

Todos los secretos viven en `.env.prod` (no versionado, `chmod 600`).

```bash
# Ver variables actuales
cat .env.prod

# Regenerar el hash de basic auth (si cambias el password de admin)
HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext 'NuevoPass')
HASH_ESCAPED="${HASH//\$/\$\$}"     # IMPORTANTE: escapar $ como $$
grep -v '^BASIC_AUTH_HASH=' .env.prod > .env.prod.tmp
printf 'BASIC_AUTH_HASH=%s\n' "$HASH_ESCAPED" >> .env.prod.tmp
mv .env.prod.tmp .env.prod
chmod 600 .env.prod

# Aplicar
cd docker
docker compose -f docker-compose.prod.yml --env-file ../.env.prod up -d --force-recreate caddy
```

---

## Añadir un módulo nuevo

```bash
# 1. Crear el repo del módulo (en GitHub): balgres-it-<nombre>
# 2. Añadirlo como submódulo en el hub
cd balgres-it-hub
git submodule add git@github.com:RafaOliX/balgres-it-<nombre>.git modules/<nombre>

# 3. Registrar el router en el backend
# Editar apps/core-api/app/main.py:
#   from <nombre> import router as <nombre>_router
#   app.include_router(<nombre>_router, prefix="/api")

# 4. Añadir dependencia del paquete Python
# Editar apps/core-api/pyproject.toml:
#   "balgres-it-<nombre> @ file:///app/modules/<nombre>/backend"

# 5. Registrar el paquete Flutter en el shell
# Editar apps/shell/pubspec.yaml:
#   balgres_it_<nombre>:
#     path: ../../modules/<nombre>/frontend

# 6. Rebuild
cd docker
docker compose up -d --build backend
```

---

## Troubleshooting

### El navegador muestra página en blanco

**Causa**: caché del Service Worker de Flutter Web (después de un deploy,
el navegador puede tener el `main.dart.js` viejo cacheado o un redirect antiguo).

**Solución**:
1. **F12** → **Application** → **Service Workers** → **Unregister**
2. **Application** → **Storage** → **Clear site data**
3. **Ctrl+Shift+R** (hard reload)

O abrir en incógnito para confirmar que es caché.

### Puerto 80 ya ocupado en el servidor

```bash
sudo ss -tlnp | grep ':80 '
```

- **Está libre** → deploy normal.
- **Ocupado por otro servicio** → dos opciones:
  - **A**: parar el otro servicio (`sudo systemctl stop X` o `docker stop <nombre>`).
  - **B**: editar `docker/docker-compose.prod.yml` y cambiar `"80:80"` por
    `"8091:80"`. Commitear el cambio así el próximo deploy lo trae.

### Desde otra PC no carga (firewall)

```bash
# Ubuntu/Debian
sudo ufw allow 80/tcp
sudo ufw status

# RHEL/Fedora
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```

### `$` del hash bcrypt rompe Caddy

**Síntoma** (en `docker compose logs caddy`):

```
parsing caddyfile tokens for 'basic_auth': username and password cannot be empty or missing
```

**Causa**: el hash bcrypt empieza por `$2a$14$...` y Docker Compose interpreta
cada `$` como variable de entorno, dejando el hash vacío cuando llega al
contenedor.

**Solución**: en `.env.prod`, el hash debe tener **`$$`** (doble dólar) en lugar
de `$` simple. `setup-server.sh` lo hace automáticamente. Si lo generas a mano:

```bash
HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext 'pass')
HASH_ESCAPED="${HASH//\$/\$\$}"
echo "BASIC_AUTH_HASH=$HASH_ESCAPED" >> .env.prod
```

Verificar:

```bash
grep BASIC_AUTH_HASH .env.prod
# Debe mostrar: BASIC_AUTH_HASH=$$2a$$14$$...
```

### Caddy devuelve 308 en lugar de servir

**Causa**: `Caddyfile.prod` tiene un dominio (ej. `app.balgres.local { ... }`)
en lugar de `:80 { ... }`. Caddy interpreta el dominio como HTTPS implícito y
redirige todo a `https://` (puerto 443 no expuesto).

**Solución**: la primera línea del `Caddyfile.prod` debe ser exactamente `:80 {`.

### `git clone` trae el repo vacío / sin submódulos

**Causa**: se clonó sin `--recurse-submodules`, o el repo está en un commit
anterior que no tiene `.gitmodules`.

**Solución**:

```bash
git submodule update --init --recursive
git submodule status                # debe mostrar un SHA, no "-"
git log --oneline -3                # debe estar en un commit reciente de main
```

Verificar el branch del repo clonado:

```bash
git branch --show-current           # debe ser "main" para deploy
git pull origin main
```

### `flutter: command not found` en WSL

Flutter se instala con `snap`, que pone el binario en `/snap/bin` — que no
está en el PATH por defecto de `zsh`.

```bash
echo 'export PATH="$PATH:/snap/bin"' >> ~/.zshrc
source ~/.zshrc
flutter --version
```

### Build de Docker se queda colgado en `FROM ghcr.io/cirruslabs/flutter`

La primera vez descarga ~1.5 GB del SDK. Es normal, tarda 5-10 min.
Si falla por red, cambiar en `docker/Dockerfile.web` a `subosito/flutter:stable`:

```dockerfile
FROM subosito/flutter:stable AS build
```

### Después de un rebuild el navegador sigue sirviendo versión vieja

Ver sección "El navegador muestra página en blanco" arriba. Es siempre caché
del Service Worker.

---

## Comandos útiles de Docker

```bash
# Estado de servicios
docker compose -f docker-compose.prod.yml --env-file ../.env.prod ps

# Logs en vivo
docker compose -f docker-compose.prod.yml --env-file ../.env.prod logs -f caddy
docker compose -f docker-compose.prod.yml --env-file ../.env.prod logs -f backend

# Shell dentro de un contenedor
docker compose -f docker-compose.prod.yml --env-file ../.env.prod exec backend sh
docker compose -f docker-compose.prod.yml --env-file ../.env.prod exec db psql -U inventario

# Bajar todo SIN borrar datos
docker compose -f docker-compose.prod.yml --env-file ../.env.prod down

# Bajar y BORRAR datos (¡cuidado en prod!)
docker compose -f docker-compose.prod.yml --env-file ../.env.prod down -v
```

---

## Backup de base de datos

```bash
# Dump comprimido con fecha
docker compose -f docker-compose.prod.yml --env-file ../.env.prod exec -T db \
  pg_dump -U inventario inventario_it | gzip > backup-$(date +%Y%m%d-%H%M).sql.gz

# Restaurar
gunzip -c backup-YYYYMMDD-HHMM.sql.gz | \
  docker compose -f docker-compose.prod.yml --env-file ../.env.prod exec -T db \
  psql -U inventario -d inventario_it
```

Recomendado: cron diario en el servidor, backup a directorio externo o NAS.

---

## Endpoints de la API (módulo inventario)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/inventario/health` | Health del módulo |
| GET | `/api/inventario/` | Listar todos los activos |
| GET | `/api/inventario/buscar?q=` | Búsqueda ILIKE por tag, categoría, marca, modelo, S/N, ubicación |
| GET | `/api/inventario/{asset_tag}` | Obtener uno por tag |
| POST | `/api/inventario/` | Crear (409 si tag o S/N duplicado) |
| PATCH | `/api/inventario/{asset_tag}` | Actualizar `status`, `location`, `notes` |
| DELETE | `/api/inventario/{asset_tag}` | Eliminar (204) |

Swagger interactivo: `http://<host>:8000/docs` en dev (backend directo, sin auth),
o `http://<host>/api/docs` si añades auth a los endpoints.

---

## Estado actual

- ✅ Backend FastAPI + PostgreSQL + CRUD completo del inventario
- ✅ Flutter Web funcionando (lista, búsqueda, filtros, formulario de alta)
- ✅ Docker dev y prod con separación limpia
- ✅ Basic auth en producción
- ✅ `setup-server.sh` bootstrap completo
- ⏳ **Pendiente**: auth JWT real (usuarios en DB, reemplaza basic auth)
- ⏳ **Pendiente**: compilar APK de Android y distribución interna
- ⏳ **Pendiente**: CI/CD con GitHub Actions
- ⏳ **Pendiente**: migraciones versionadas (Alembic) cuando evolucione el esquema

---

## Contribuir

- Rama `develop`: integración / QA. Todo el trabajo nuevo va aquí.
- Rama `main`: producción. Solo se actualiza haciendo merge desde `develop`
  cuando algo está probado.
- Los submódulos también tienen su `develop` y `main` propios. Al actualizar
  un módulo: primero push en el módulo, luego `git add modules/<nombre>` en
  el hub y push.

Commits con prefijo entre corchetes: `[inventario] ...`, `[deploy] ...`,
`[hub] ...`.

---



Sistema centralizado de gestión de activos (Inventario) para el departamento de IT de Balgres. 
Construido con **Flutter (Web/Android)**, **FastAPI (Python)** y **PostgreSQL**, orquestado con **Docker Compose**.

## Arquitectura

- **`apps/core-api`**: Backend principal en FastAPI.
- **`apps/shell`**: Interfaz Flutter (Web y Android).
- **`modules/inventario`**: Submódulo con la lógica del inventario (Backend + Frontend).
- **`docker/`**: Archivos de orquestación y despliegue.

---

## 🚀 Quickstart (Montar en una PC nueva)

### Requisitos previos
- Sistema operativo: Linux o WSL2 (Windows).
- Tener instalado: `git`, `docker`, `docker-compose`.
- *(Opcional)* Para compilar el APK: `docker` (se compila dentro de un contenedor).

### Instalación en 3 pasos

**1. Clonar el repositorio CON sus submódulos:**
```bash



## Backup y restore

### Crear un backup

```bash
./scripts/backup.sh
Genera en ~/backups/balgres-it-hub/:

Archivo	Contenido
db-YYYYMMDD-HHMM.sql.gz	Dump completo de PostgreSQL (~7 KB)
uploads-YYYYMMDD-HHMM.tar.gz	Fotos de los activos (~27 MB, prefijo uploads/)
env-YYYYMMDD-HHMM.prod	.env.prod con permisos 600 (contiene secretos)
El script valida antes de dar OK:

Backend y DB están Up/healthy.

El dump no está vacío, es gzip válido, tiene ≥100 líneas.

Contiene las 8 tablas esperadas (it_assets, employees, etc.).

No contiene tablas residuales (contactos, etc.).

El tar de uploads tiene ≥1 imagen.

.env.prod tiene DB_PASSWORD y BASIC_AUTH_HASH.

Si cualquier validación falla, borra los archivos parciales y aborta. No te deja un .sql.gz de 20 bytes como passaba antes.

Restaurar
bash
./scripts/restore.sh YYYYMMDD-HHMM
El script:

Valida el backup antes de tocar nada (gzip válido, 8 tablas, imágenes).

Pide confirmación (y minúscula).

Crea backup de seguridad: db-pre-restore-YYYYMMDD-HHMM.sql.gz.

Para el backend.

DROP SCHEMA public CASCADE + restore del dump.

Verifica que las 8 tablas existen en la DB post-restore.

Borra el volumen balgres-it-hub_uploads, lo recrea, extrae el tar con --strip-components=1.

Levanta el backend y verifica /docs.

Si algo falla a mitad, imprime la ruta del backup de seguridad y aborta sin dejar la DB a medias.

Backup manual (sin script)
bash
cd docker
C=(docker compose -f docker-compose.prod.yml --env-file ../.env.prod)

# DB
"${C[@]}" exec -T db pg_dump -U inventario inventario_it | gzip > db.sql.gz

# Uploads (el tar trae prefijo uploads/, por eso --strip-components=1 al restaurar)
"${C[@]}" cp backend:/app/uploads - 2>/dev/null | gzip > uploads.tar.gz

# Restore DB
"${C[@]}" exec -T db psql -U inventario -d inventario_it \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO inventario;"
gunzip -c db.sql.gz | "${C[@]}" exec -T db psql -U inventario -d inventario_it

# Restore uploads
docker volume rm -f balgres-it-hub_uploads
docker volume create balgres-it-hub_uploads
docker run --rm -v balgres-it-hub_uploads:/data -v "$PWD":/backup:ro \
  alpine sh -c "cd /data && tar xzf /backup/uploads.tar.gz --strip-components=1"
Verificar un restore
bash
curl -u admin:PASS http://localhost:8091/api/inventario/health
curl -u admin:PASS http://localhost:8091/api/inventario/ | python3 -m json.tool | head -20
Abrir http://localhost:8091/ en el navegador:

Activos listados con fotos cargando.

Menú ⋮ → Empleados con datos.

Dashboard con conteos no-cero.

Automatización (cron diario)
bash
crontab -e
text
0 2 * * * cd /home/devro/projects/work/balgres-it-hub && ./scripts/backup.sh >> /home/devro/backups/cron.log 2>&1
Copia externa (obligatoria)
Los backups viven en ~/backups/balgres-it-hub/ dentro de WSL. Si borras WSL, los pierdes. Copia semanalmente a Windows / Drive / USB:

bash
# Ajusta tu usuario de Windows
rsync -av ~/backups/balgres-it-hub/ /mnt/c/Users/RafaelO/Desktop/balgres-backups/
Retención
El script no borra backups viejos automáticamente. Política manual sugerida:

bash
# Ver qué hay
ls -lh ~/backups/balgres-it-hub/

# Borrar backups con más de 30 días (excepto db-pre-restore-*)
find ~/backups/balgres-it-hub -name "*-*.sql.gz" -mtime +30 ! -name "db-pre-restore-*" -delete
find ~/backups/balgres-it-hub -name "*-*.tar.gz" -mtime +30 -delete
Nunca borres sin tener copia externa verificada.
