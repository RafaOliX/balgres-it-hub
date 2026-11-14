#!/usr/bin/env bash
# Backup -> build -> up -> espera salud. Aborta si algo falla (los datos quedan intactos).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

echo "==> Desplegando instancia '$PROJECT' (puerto $HUB_PORT, rama $(git rev-parse --abbrev-ref HEAD))"
"$ROOT/scripts/backup.sh"
"${COMPOSE[@]}" build backend
"${COMPOSE[@]}" build caddy
"${COMPOSE[@]}" up -d

echo "Esperando al backend..."
if ! wait_backend; then
  "${COMPOSE[@]}" logs --tail=80 backend
  echo "FALLO: el backend no responde (los datos siguen intactos; backup en $DEST)"; exit 1
fi
echo -n "Índices en it_assets: "
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -tAc "select count(*) from pg_indexes where tablename='it_assets'"
echo "✅ Desplegado: http://localhost:$HUB_PORT"
