# Variables comunes. Se usa con: source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env.prod"

# Lee VAR de .env.prod sin "source" (el hash lleva $$ y se rompería)
env_get() { [ -f "$ENV_FILE" ] && { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- || true; } || true; }

PROJECT="$(env_get COMPOSE_PROJECT_NAME)"; PROJECT="${PROJECT:-balgres-it-hub}"
HUB_PORT="$(env_get HUB_PORT)";            HUB_PORT="${HUB_PORT:-8091}"
DB_USER="$(env_get DB_USER)";              DB_USER="${DB_USER:-inventario}"
DB_NAME="$(env_get DB_NAME)";              DB_NAME="${DB_NAME:-inventario_it}"
DEST="${BACKUP_DIR:-$HOME/backups/$PROJECT}"

COMPOSE=(docker compose -p "$PROJECT" -f "$ROOT/docker/docker-compose.prod.yml" --env-file "$ENV_FILE")

wait_backend() {  # espera activa (hasta ~60 s)
  for _ in $(seq 1 30); do
    if "${COMPOSE[@]}" exec -T backend curl -fsS http://localhost:8000/api/inventario/health >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
