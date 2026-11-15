#!/usr/bin/env bash
# Uso: ./scripts/restore.sh <stamp>
# Para copiar datos de OTRA instancia: BACKUP_DIR=~/backups/balgres-it-hub ./scripts/restore.sh <stamp>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

REQUIRED=(acta_templates categories employees it_asset_assignments it_asset_history it_asset_images it_assets locations)
OPTIONAL=(subnets ip_addresses roles users notas)   # si faltan (dump antiguo), el backend las crea al arrancar

fail() { echo ""; echo "❌ $*"; exit 1; }

if [ $# -ne 1 ]; then
  echo "Uso: $0 <stamp>   (backups en $DEST)"
  ls -1 "$DEST"/db-*.sql.gz 2>/dev/null | sed 's/.*db-//; s/\.sql\.gz//' || echo "  (ninguno)"
  exit 1
fi
STAMP="$1"
DB_FILE="$DEST/db-$STAMP.sql.gz"; UP_FILE="$DEST/uploads-$STAMP.tar.gz"; SUMS="$DEST/sums-$STAMP.txt"
VOL="${PROJECT}_uploads"

echo "[0/5] Validando backup..."
[ -s "$DB_FILE" ] || fail "falta o está vacío $DB_FILE"
[ -s "$UP_FILE" ] || fail "falta o está vacío $UP_FILE"
gunzip -t "$DB_FILE" 2>/dev/null || fail "dump no es gzip válido."
gunzip -t "$UP_FILE" 2>/dev/null || fail "tar no es gzip válido."
if [ -f "$SUMS" ]; then ( cd "$DEST" && sha256sum -c "sums-$STAMP.txt" --quiet ) || fail "checksum no coincide: backup alterado o corrupto."; else echo "   (sin sums, backup antiguo)"; fi
TABLES=$(gunzip -c "$DB_FILE" | grep -oE "^COPY public\.[a-z_]+" | sed 's/^COPY public\.//' | sort -u)
MISSING=""; for t in "${REQUIRED[@]}"; do echo "$TABLES" | grep -qx "$t" || MISSING="$MISSING $t"; done
[ -z "$MISSING" ] || fail "el dump NO contiene tablas:$MISSING"
for t in "${OPTIONAL[@]}"; do echo "$TABLES" | grep -qx "$t" || echo "   ⚠ el dump no trae '$t' (se creará vacía al arrancar)"; done

echo ""; echo "⚠️  Esto REEMPLAZA la DB y las fotos de la instancia '$PROJECT' (puerto $HUB_PORT)."
read -rp "¿Continuar? [y/N] " ok
[ "$ok" = "y" ] || { echo "Cancelado"; exit 0; }

mkdir -p "$DEST"
echo "[1/5] Backup de seguridad..."
SAFE="$DEST/db-pre-restore-$(date +%Y%m%d-%H%M).sql.gz"
"${COMPOSE[@]}" exec -T db pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$SAFE" || fail "backup de seguridad falló."
gunzip -t "$SAFE" 2>/dev/null || fail "backup de seguridad inválido."
echo "   ✓ $SAFE"

echo "[2/5] Parando backend..."
"${COMPOSE[@]}" stop backend >/dev/null

echo "[3/5] Restaurando DB..."
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO \"$DB_USER\";" >/dev/null \
  || fail "no se pudo limpiar el esquema. Seguridad en: $SAFE"
if ! gunzip -c "$DB_FILE" | "${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -1 >/dev/null; then
  fail "el restore falló (transacción revertida). Backup de seguridad: $SAFE"
fi
N=$("${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT COUNT(*) FROM it_assets;")
echo "   ✓ restaurado ($N activos)"

echo "[4/5] Restaurando uploads..."
docker volume create "$VOL" >/dev/null 2>&1 || true
docker run --rm -v "$VOL":/data alpine sh -c 'find /data -mindepth 1 -delete'
docker run --rm -v "$VOL":/data -v "$DEST":/backup:ro alpine \
  sh -c "cd /data && tar xzf /backup/uploads-$STAMP.tar.gz --strip-components=1"
echo "   ✓ $(docker run --rm -v "$VOL":/data alpine sh -c 'ls /data | wc -l' | tr -d ' \n') archivos"

echo "[5/5] Levantando backend..."
"${COMPOSE[@]}" start backend >/dev/null
wait_backend || fail "el backend no responde. Revisa: ./scripts/compose.sh logs backend"

echo ""; echo "✅ Restore completo → http://localhost:$HUB_PORT"
echo "Si algo se ve mal, vuelve atrás con: ./scripts/restore.sh ${SAFE##*/db-}  (en BACKUP_DIR=$DEST)"
