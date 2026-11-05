#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: instala Docker primero:"
  echo "  curl -fsSL https://get.docker.com | sh"
  echo "  sudo usermod -aG docker \$USER && newgrp docker"
  exit 1
fi

[ -f modules/inventario/backend/pyproject.toml ] || git submodule update --init --recursive

if [ ! -f .env.prod ]; then
  echo "==> Generando .env.prod con secretos aleatorios..."
  cp .env.prod.example .env.prod
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)|" .env.prod
  sed -i "s|JWT_SECRET=.*|JWT_SECRET=$(openssl rand -base64 48 | tr -d '/+=' | head -c 48)|" .env.prod
  chmod 600 .env.prod
fi

if grep -q "REEMPLAZA_ESTO_CON_TU_HASH" docker/Caddyfile.prod; then
  echo "ERROR: docker/Caddyfile.prod tiene el hash sin reemplazar."
  echo "  Genera: docker run --rm caddy:2-alpine caddy hash-password --plaintext 'TuPass'"
  exit 1
fi

echo "==> Puerto 80:"
ss -tlnp 2>/dev/null | grep ":80 " || echo "  OK libre"

echo "==> Build (primera vez ~10 min)..."
cd docker
docker compose -f docker-compose.prod.yml --env-file ../.env.prod build

echo "==> Up..."
docker compose -f docker-compose.prod.yml --env-file ../.env.prod up -d

echo "==> Estado:"
docker compose -f docker-compose.prod.yml ps

echo
echo "✔ Verifica: curl -u admin:TuPass http://localhost/api/inventario/health"
echo "✔ Abre:     http://<IP-del-servidor>/"
