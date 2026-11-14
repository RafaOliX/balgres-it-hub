#!/usr/bin/env bash
# Ejecuta docker compose contra ESTA instancia: ./scripts/compose.sh ps
set -euo pipefail
source "$(dirname "$0")/lib.sh"
exec "${COMPOSE[@]}" "$@"
