#!/usr/bin/env bash
# Uso: ./scripts/test.sh [backend|frontend|all]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHAT="${1:-all}"

if [[ "$WHAT" == "backend" || "$WHAT" == "all" ]]; then
  echo "== Backend (pytest, SQLite temporal) =="
  cd "$ROOT/docker"
  docker compose -f docker-compose.prod.yml --env-file ../.env.prod run --rm --no-deps \
    -v "$ROOT/modules/inventario/backend:/app/modules/inventario/backend" \
    -v "$ROOT/modules/contacts/backend:/app/modules/contacts/backend" \
    -v "$ROOT/modules/redes/backend:/app/modules/redes/backend" \
    backend sh -c "pip install -q pytest httpx && cd /app/modules/inventario/backend && python -m pytest -q tests"
fi

if [[ "$WHAT" == "frontend" || "$WHAT" == "all" ]]; then
  echo "== Frontend (flutter test) =="
  docker run --rm -v "$ROOT:/repo" -w /repo/modules/inventario/frontend \
    ghcr.io/cirruslabs/flutter:stable sh -c "cd /repo/modules/contacts/frontend && flutter pub get && flutter test && cd /repo/modules/inventario/frontend && flutter pub get && flutter test && cd /repo/modules/redes/frontend && flutter pub get && flutter test"
fi
