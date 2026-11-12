#!/usr/bin/env bash
# Backup -> build -> up -> espera salud -> verifica. Aborta si algo falla.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/docker"
C=(docker compose -f docker-compose.prod.yml --env-file ../.env.prod)

"$ROOT/scripts/backup.sh"
"${C[@]}" build backend
"${C[@]}" build caddy
"${C[@]}" up -d

echo "Esperando al backend..."
ok=0
for _ in $(seq 1 30); do
  if "${C[@]}" exec -T backend curl -fsS http://localhost:8000/api/inventario/health >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
if [ "$ok" != 1 ]; then
  "${C[@]}" logs --tail=80 backend
  echo "FALLO: el backend no responde (los datos siguen intactos; el backup está en ~/backups)"; exit 1
fi
echo -n "Índices en it_assets: "
"${C[@]}" exec -T db psql -U inventario -d inventario_it -tAc "select count(*) from pg_indexes where tablename='it_assets'"
echo "OK: desplegado"
