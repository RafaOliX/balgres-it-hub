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
  DB_PASS=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
  JWT_SEC=$(openssl rand -base64 48 | tr -d '/+=' | head -c 48)
  # Usamos printf para evitar que el $ del hash se expanda
  {
    echo "DB_USER=inventario"
    printf 'DB_PASSWORD=%s\n' "$DB_PASS"
    echo "DB_NAME=inventario_it"
    printf 'JWT_SECRET=%s\n' "$JWT_SEC"
    echo "BASIC_AUTH_HASH=REEMPLAZA_CON_HASH_BCRYPT"
  } > .env.prod
  chmod 600 .env.prod
fi

if grep -q "REEMPLAZA_CON_HASH_BCRYPT" .env.prod; then
  echo "==> Generando hash de basic auth..."
  read -rsp "Password para usuario 'admin': " ADMIN_PASS
  echo
  [ -n "$ADMIN_PASS" ] || { echo "ERROR: password vacío"; exit 1; }
  HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "$ADMIN_PASS")
  # Reescribir la línea con printf para no expandir $
  grep -v '^BASIC_AUTH_HASH=' .env.prod > .env.prod.tmp
  printf 'BASIC_AUTH_HASH=%s\n' "$HASH" >> .env.prod.tmp
  mv .env.prod.tmp .env.prod
  chmod 600 .env.prod
  echo "    Hash guardado en .env.prod"
fi

echo "==> Puerto 80:"
ss -tlnp 2>/dev/null | grep ":80 " || echo "  OK libre"

echo "==> Build (primera vez ~10 min por Flutter SDK)..."
cd docker
docker compose -f docker-compose.prod.yml --env-file ../.env.prod build

echo "==> Up..."
docker compose -f docker-compose.prod.yml --env-file ../.env.prod up -d

echo "==> Estado:"
docker compose -f docker-compose.prod.yml ps

echo
echo "✔ Verifica: curl -u admin:TU_PASSWORD http://localhost/api/inventario/health"
echo "✔ Abre:     http://<IP-del-servidor>/"
