#!/usr/bin/env bash
# Uso: ./scripts/setup-server.sh [puerto] [nombre-instancia]
#   ./scripts/setup-server.sh                                  -> principal (8091, balgres-it-hub)
#   ./scripts/setup-server.sh 8092 balgres-it-hub-test         -> instancia de pruebas
set -euo pipefail
cd "$(dirname "$0")/.."
ARG_PORT="${1:-}"; ARG_NAME="${2:-}"
source scripts/lib.sh

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: necesitas Docker con Compose v2:"
  echo "  curl -fsSL https://get.docker.com | sh"
  echo "  sudo usermod -aG docker \$USER && newgrp docker"
  exit 1
fi
command -v openssl >/dev/null || { echo "ERROR: instala openssl (sudo apt install -y openssl)"; exit 1; }

if [ ! -f .env.prod ]; then
  NAME="${ARG_NAME:-balgres-it-hub}"; PORT="${ARG_PORT:-8091}"
  if docker volume inspect "${NAME}_pgdata" >/dev/null 2>&1; then
    echo "ERROR: existe el volumen ${NAME}_pgdata pero no hay .env.prod."
    echo "  Si es esta instancia: restaura el env-*.prod de tu backup como .env.prod."
    echo "  Si quieres empezar limpio: docker volume rm ${NAME}_pgdata ${NAME}_uploads (BORRA datos)."
    exit 1
  fi
  echo "==> Generando .env.prod ($NAME, puerto $PORT)..."
  PING=5; [ "$NAME" = "balgres-it-hub" ] || PING=0   # las pruebas no escanean la red
  {
    echo "COMPOSE_PROJECT_NAME=$NAME"
    echo "HUB_PORT=$PORT"
    echo "DB_USER=inventario"
    printf 'DB_PASSWORD=%s\n' "$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)"
    echo "DB_NAME=inventario_it"
    printf 'JWT_SECRET=%s\n' "$(openssl rand -base64 48 | tr -d '/+=' | head -c 48)"
    echo "REDES_PING_MINUTES=$PING"
    echo "# ADMIN_PASSWORD=   (opcional: si se deja vacío se genera una temporal y se pide cambiarla)"
  } > .env.prod
  chmod 600 .env.prod
  source scripts/lib.sh   # recarga con los valores nuevos
else
  echo "==> Usando .env.prod existente (instancia '$PROJECT', puerto $HUB_PORT)"
  { [ -z "$ARG_PORT" ] || [ "$ARG_PORT" = "$HUB_PORT" ]; } || echo "   AVISO: ignoro el puerto $ARG_PORT; edita HUB_PORT en .env.prod si quieres cambiarlo."
fi

if [ -z "$("${COMPOSE[@]}" ps -q caddy 2>/dev/null)" ] && ss -tln 2>/dev/null | grep -q ":$HUB_PORT "; then
  echo "ERROR: el puerto $HUB_PORT está ocupado. Cambia HUB_PORT en .env.prod y repite."
  exit 1
fi

echo "==> Build (la primera vez tarda ~10 min por el SDK de Flutter)..."
"${COMPOSE[@]}" build
echo "==> Levantando..."
"${COMPOSE[@]}" up -d

echo "==> Esperando al backend..."
if ! wait_backend; then
  "${COMPOSE[@]}" logs --tail=80 backend
  echo "FALLO: el backend no responde."; exit 1
fi

echo
echo "✔ Instancia '$PROJECT' lista:  http://localhost:$HUB_PORT"
echo "  Usuario: admin"
PW="$("${COMPOSE[@]}" logs backend 2>/dev/null | grep '\[auth\]' | tail -1 || true)"
[ -n "$PW" ] && echo "  $PW" || echo "  (la contraseña de admin ya existía; si la olvidaste, resetea desde Usuarios)"
