#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

STAMP=$(date +%Y%m%d-%H%M)
mkdir -p "$DEST"

EXPECTED_TABLES=(
  acta_templates categories employees it_asset_assignments it_asset_history
  it_asset_images it_assets locations subnets ip_addresses roles users
)
# Módulos recién añadidos: si la instancia aún no los desplegó, solo avisa (no aborta)
OPTIONAL_TABLES=(notas nota_activos nota_diagramas planos plano_pins plano_trazos)

fail() {
  echo ""; echo "❌ $*"; echo "   Backup abortado. Archivos parciales borrados."
  rm -f "$DEST/db-$STAMP.sql.gz" "$DEST/uploads-$STAMP.tar.gz" "$DEST/env-$STAMP.prod" "$DEST/sums-$STAMP.txt"
  exit 1
}

echo "[0/4] Verificando entorno ($PROJECT)..."
[ -f "$ENV_FILE" ] || fail "falta .env.prod"
PS="$("${COMPOSE[@]}" ps --format '{{.Service}} {{.Status}}' 2>/dev/null || true)"
echo "$PS" | grep -q "^backend Up" || fail "backend no está Up."
echo "$PS" | grep -q "^db Up.*healthy" || fail "db no está healthy."

echo "[1/4] DB..."
"${COMPOSE[@]}" exec -T db pg_dump -U "$DB_USER" --no-owner --no-privileges \
  --exclude-table-data=auth_sessions "$DB_NAME" | gzip > "$DEST/db-$STAMP.sql.gz" || fail "pg_dump falló."
[ -s "$DEST/db-$STAMP.sql.gz" ] || fail "dump vacío."
gunzip -t "$DEST/db-$STAMP.sql.gz" 2>/dev/null || fail "dump no es gzip válido."
LINES=$(gunzip -c "$DEST/db-$STAMP.sql.gz" | wc -l)
[ "$LINES" -ge 100 ] || fail "dump con solo $LINES líneas."
FOUND=$(gunzip -c "$DEST/db-$STAMP.sql.gz" | grep -oE "^COPY public\.[a-z_]+" | sed 's/^COPY public\.//' | sort -u)
MISSING=""
for t in "${EXPECTED_TABLES[@]}"; do echo "$FOUND" | grep -qx "$t" || MISSING="$MISSING $t"; done
[ -z "$MISSING" ] || fail "el dump no contiene tablas:$MISSING"
for t in "${OPTIONAL_TABLES[@]}"; do echo "$FOUND" | grep -qx "$t" || echo "   ⚠ el dump no trae '$t' (módulo aún no desplegado)"; done
echo "   ✓ $LINES líneas, ${#EXPECTED_TABLES[@]} tablas"

echo "[2/4] Uploads..."
"${COMPOSE[@]}" cp backend:/app/uploads - 2>/dev/null | gzip > "$DEST/uploads-$STAMP.tar.gz" || fail "copia de uploads falló."
gunzip -t "$DEST/uploads-$STAMP.tar.gz" 2>/dev/null || fail "tar de uploads no es gzip válido."
NFILES=$(gunzip -c "$DEST/uploads-$STAMP.tar.gz" | tar tf - 2>/dev/null | grep -cE '\.(png|jpg|jpeg|webp)$' || true)
echo "   ✓ $NFILES imágenes"

echo "[3/4] .env.prod..."
cp "$ENV_FILE" "$DEST/env-$STAMP.prod"; chmod 600 "$DEST/env-$STAMP.prod"
grep -q '^DB_PASSWORD=' "$DEST/env-$STAMP.prod" || fail "env sin DB_PASSWORD."

echo "[4/4] Checksums..."
( cd "$DEST" && sha256sum "db-$STAMP.sql.gz" "uploads-$STAMP.tar.gz" "env-$STAMP.prod" > "sums-$STAMP.txt" )

echo ""; echo "✅ Backup OK ($PROJECT)"
ls -lh "$DEST/db-$STAMP.sql.gz" "$DEST/uploads-$STAMP.tar.gz" "$DEST/env-$STAMP.prod"
echo "Restaurar: ./scripts/restore.sh $STAMP"
