#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${BACKUP_DIR:-$HOME/backups/balgres-it-hub}"
STAMP=$(date +%Y%m%d-%H%M)
COMPOSE=(docker compose -f docker/docker-compose.prod.yml --env-file .env.prod)
mkdir -p "$DEST"

# Tablas que el dump DEBE contener. Si falta alguna, la DB está rota.
EXPECTED_TABLES=(
  acta_templates categories employees it_asset_assignments
  it_asset_history it_asset_images it_assets locations
)
# Tablas residuales que NO deben aparecer (restos de refactors cancelados).
FORBIDDEN_TABLES=(contactos contactos_old empleado_old)

fail() {
  echo ""
  echo "❌ $*"
  echo "   Backup abortado. Archivos parciales borrados."
  rm -f "$DEST/db-$STAMP.sql.gz" "$DEST/uploads-$STAMP.tar.gz" "$DEST/env-$STAMP.prod"
  exit 1
}

# ── 0. Pre-flight
echo "[0/4] Verificando entorno..."
"${COMPOSE[@]}" ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -q "balgres-it-hub-backend-1 Up" \
  || fail "backend no está Up. Arráncalo antes de hacer backup."
"${COMPOSE[@]}" ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -q "balgres-it-hub-db-1 Up.*healthy" \
  || fail "db no está healthy."
[ -f .env.prod ] || fail "falta .env.prod en la raíz del repo."

# ── 1. DB
echo "[1/4] DB..."
"${COMPOSE[@]}" exec -T db pg_dump -U inventario inventario_it \
  | gzip > "$DEST/db-$STAMP.sql.gz"

# validaciones DB
[ -s "$DEST/db-$STAMP.sql.gz" ] || fail "dump DB vacío (0 bytes)."
gunzip -t "$DEST/db-$STAMP.sql.gz" 2>/dev/null || fail "dump DB no es gzip válido."
LINES=$(gunzip -c "$DEST/db-$STAMP.sql.gz" | wc -l)
[ "$LINES" -ge 100 ] || fail "dump DB tiene solo $LINES líneas (esperado >=100)."

FOUND_TABLES=$(gunzip -c "$DEST/db-$STAMP.sql.gz" | grep -oE "^COPY public\.[a-z_]+" | sed 's/^COPY public\.//' | sort -u)
MISSING=""
for t in "${EXPECTED_TABLES[@]}"; do
  echo "$FOUND_TABLES" | grep -qx "$t" || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] || fail "dump DB no contiene tablas: $MISSING"

FORBIDDEN_FOUND=""
for t in "${FORBIDDEN_TABLES[@]}"; do
  echo "$FOUND_TABLES" | grep -qx "$t" && FORBIDDEN_FOUND="$FORBIDDEN_FOUND $t"
done
[ -z "$FORBIDDEN_FOUND" ] || fail "dump DB contiene tablas residuales:$FORBIDDEN_FOUND — bórralas antes de hacer backup."

echo "   ✓ $LINES líneas, ${#EXPECTED_TABLES[@]} tablas, sin residuos"

# ── 2. Uploads
echo "[2/4] Uploads..."
"${COMPOSE[@]}" cp backend:/app/uploads - 2>/dev/null \
  | gzip > "$DEST/uploads-$STAMP.tar.gz"

[ -s "$DEST/uploads-$STAMP.tar.gz" ] || fail "tar uploads vacío."
gunzip -t "$DEST/uploads-$STAMP.tar.gz" 2>/dev/null || fail "tar uploads no es gzip válido."
NFILES=$(gunzip -c "$DEST/uploads-$STAMP.tar.gz" | tar tf - 2>/dev/null | grep -cE '\.(png|jpg|jpeg|webp)$' || true)
[ "$NFILES" -ge 1 ] || fail "tar uploads no contiene imágenes (posible tar corrupto)."

echo "   ✓ $NFILES imágenes"

# ── 3. .env.prod
echo "[3/4] .env.prod..."
cp .env.prod "$DEST/env-$STAMP.prod"
chmod 600 "$DEST/env-$STAMP.prod"
grep -q '^DB_PASSWORD=' "$DEST/env-$STAMP.prod" || fail "env-$STAMP.prod no tiene DB_PASSWORD."
grep -q '^BASIC_AUTH_HASH=' "$DEST/env-$STAMP.prod" || fail "env-$STAMP.prod no tiene BASIC_AUTH_HASH."
echo "   ✓ claves DB_PASSWORD y BASIC_AUTH_HASH presentes"

# ── 4. Resumen
echo ""
echo "[4/4] Backup OK"
ls -lh "$DEST/db-$STAMP.sql.gz" "$DEST/uploads-$STAMP.tar.gz" "$DEST/env-$STAMP.prod"
echo ""
echo "Para restaurar: ./scripts/restore.sh $STAMP"
