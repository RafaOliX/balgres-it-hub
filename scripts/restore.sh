#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${BACKUP_DIR:-$HOME/backups/balgres-it-hub}"
COMPOSE=(docker compose -f docker/docker-compose.prod.yml --env-file .env.prod)

EXPECTED_TABLES=(
  acta_templates categories employees it_asset_assignments
  it_asset_history it_asset_images it_assets locations
)

if [ $# -ne 1 ]; then
  echo "Uso: $0 <stamp>"
  echo "Ejemplo: $0 20261112-1550"
  echo ""
  echo "Backups disponibles:"
  ls -1 "$DEST"/db-*.sql.gz 2>/dev/null \
    | sed 's/.*db-//; s/\.sql\.gz//' || echo "  (ninguno)"
  exit 1
fi

STAMP="$1"
DB_FILE="$DEST/db-$STAMP.sql.gz"
UP_FILE="$DEST/uploads-$STAMP.tar.gz"
ENV_FILE="$DEST/env-$STAMP.prod"

fail() {
  echo ""
  echo "❌ $*"
  exit 1
}

# ── 0. Pre-flight: validar backups ANTES de tocar nada
echo "[0/5] Validando archivos de backup..."
[ -f "$DB_FILE" ]  || fail "falta $DB_FILE"
[ -f "$UP_FILE" ]  || fail "falta $UP_FILE"
[ -s "$DB_FILE" ]  || fail "dump DB vacío."
[ -s "$UP_FILE" ]  || fail "tar uploads vacío."
gunzip -t "$DB_FILE" 2>/dev/null || fail "dump DB no es gzip válido."
gunzip -t "$UP_FILE" 2>/dev/null || fail "tar uploads no es gzip válido."

DB_TABLES=$(gunzip -c "$DB_FILE" | grep -oE "^COPY public\.[a-z_]+" | sed 's/^COPY public\.//' | sort -u)
MISSING=""
for t in "${EXPECTED_TABLES[@]}"; do
  echo "$DB_TABLES" | grep -qx "$t" || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] || fail "el dump NO contiene tablas: $MISSING — backup corrupto o incompleto."

IMG_COUNT=$(gunzip -c "$UP_FILE" | tar tf - 2>/dev/null | grep -cE '\.(png|jpg|jpeg|webp)$' || true)
[ "$IMG_COUNT" -ge 1 ] || fail "el tar no contiene imágenes."

echo "   ✓ DB: $(du -h "$DB_FILE" | cut -f1), $IMG_COUNT imágenes, ${#EXPECTED_TABLES[@]} tablas"

echo ""
echo "⚠️  Esto REEMPLAZA la DB y los uploads actuales."
echo "   Backup: $STAMP"
read -p "¿Continuar? [y/N] " ok
[ "$ok" = "y" ] || { echo "Cancelado"; exit 0; }

# ── 1. Backup de seguridad
echo ""
echo "[1/5] Backup de seguridad de la DB actual..."
SAFE="$DEST/db-pre-restore-$(date +%Y%m%d-%H%M).sql.gz"
"${COMPOSE[@]}" exec -T db pg_dump -U inventario inventario_it | gzip > "$SAFE"
gunzip -t "$SAFE" 2>/dev/null || fail "backup de seguridad falló (gzip inválido)."
echo "   ✓ $SAFE"

# ── 2. Parar backend
echo "[2/5] Parar backend..."
"${COMPOSE[@]}" stop backend >/dev/null
echo "   ✓ parado"

# ── 3. Restaurar DB
echo "[3/5] Restaurar DB..."
"${COMPOSE[@]}" exec -T db psql -U inventario -d inventario_it \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO inventario;" \
  >/dev/null

RESTORE_LOG=$(gunzip -c "$DB_FILE" \
  | "${COMPOSE[@]}" exec -T db psql -U inventario -d inventario_it 2>&1 || true)

if echo "$RESTORE_LOG" | grep -qiE "^ERROR"; then
  echo "$RESTORE_LOG" | grep -iE "^ERROR" | head -10
  fail "el restore produjo errores. Backup de seguridad en: $SAFE"
fi

# validar tablas post-restore
ACTUAL_TABLES=$("${COMPOSE[@]}" exec -T db psql -U inventario -d inventario_it -At \
  -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")
MISSING=""
for t in "${EXPECTED_TABLES[@]}"; do
  echo "$ACTUAL_TABLES" | grep -qx "$t" || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] || fail "post-restore faltan tablas: $MISSING. Restaurar backup de seguridad: ./scripts/restore.sh ${SAFE##*/db-pre-restore-}"

# validar que hay datos en it_assets (no solo schema)
N_ASSETS=$("${COMPOSE[@]}" exec -T db psql -U inventario -d inventario_it -At \
  -c "SELECT COUNT(*) FROM it_assets;")
echo "   ✓ ${#EXPECTED_TABLES[@]} tablas, $N_ASSETS activos"

# ── 4. Restaurar uploads
echo "[4/5] Restaurar uploads..."
docker volume rm -f balgres-it-hub_uploads >/dev/null 2>&1 || true
docker volume create balgres-it-hub_uploads >/dev/null
docker run --rm \
  -v balgres-it-hub_uploads:/data \
  -v "$DEST":/backup:ro \
  alpine sh -c "cd /data && tar xzf /backup/uploads-$STAMP.tar.gz --strip-components=1"

UP_RESTORED=$(docker run --rm -v balgres-it-hub_uploads:/data alpine \
  sh -c "ls /data | wc -l" | tr -d ' \n')
[ "$UP_RESTORED" -ge 1 ] || fail "el volumen uploads quedó vacío tras el restore."
echo "   ✓ $UP_RESTORED archivos en /app/uploads"

# ── 5. Levantar backend
echo "[5/5] Levantar backend..."
"${COMPOSE[@]}" start backend >/dev/null
sleep 6

# health check

HEALTH=$("${COMPOSE[@]}" exec -T backend python -c \
  "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/docs', timeout=5).status)" 2>/dev/null || echo "fail")
if [ "$HEALTH" != "200" ]; then
  echo "   ⚠️  backend no responde /health todavía. Revisa: docker compose logs backend"
else
  echo "   ✓ backend /health = 200"
fi

echo ""
echo "✅ Restore completo"
echo ""
echo "Verificar en navegador: http://localhost:8091/"
echo "Si algo falla, backup de seguridad en: $SAFE"
