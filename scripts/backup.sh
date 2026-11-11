#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../docker"
DEST="${BACKUP_DIR:-$HOME/backups/balgres-it-hub}"
STAMP=$(date +%Y%m%d-%H%M)
COMPOSE=(docker compose -f docker-compose.prod.yml --env-file ../.env.prod)
mkdir -p "$DEST"
"${COMPOSE[@]}" exec -T db pg_dump -U inventario inventario_it | gzip > "$DEST/db-$STAMP.sql.gz"
"${COMPOSE[@]}" cp backend:/app/uploads - | gzip > "$DEST/uploads-$STAMP.tar.gz"
find "$DEST" -type f -mtime +14 -delete
echo "Backup OK en $DEST ($STAMP)"
