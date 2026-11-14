#!/usr/bin/env bash
# Se ejecuta en la carpeta de MAIN: une develop -> main y despliega esta instancia.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "❌ Ejecuta esto en la carpeta que tiene la rama main."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "❌ Hay cambios sin commitear en main."; exit 1; }
git fetch origin --quiet || echo "⚠ sin conexión a origin, uso lo local"
if [ -n "$(git rev-list develop..origin/develop 2>/dev/null)" ]; then
  echo "❌ origin/develop tiene commits que tu develop local no. Haz 'git pull' en la carpeta de pruebas primero."; exit 1
fi
NEW="$(git log --oneline main..develop)"
[ -n "$NEW" ] || { echo "Nada que promover: main ya tiene todo develop."; exit 0; }

echo "Cambios que entrarán a main:"; echo "$NEW"; echo
read -rp "¿Probaste esto en la instancia de pruebas y quieres pasarlo a producción? [y/N] " ok
[ "$ok" = "y" ] || { echo "Cancelado"; exit 0; }

PREV="$(git rev-parse HEAD)"
git merge --no-ff develop -m "[hub] Release: merge develop -> main"
if ! "$ROOT/scripts/deploy.sh"; then
  echo ""; echo "❌ El despliegue falló. Para volver al código anterior:"
  echo "   git reset --hard $PREV && ./scripts/deploy.sh"
  echo "   (la DB tiene backup previo en $DEST; las migraciones del backend solo añaden columnas/índices)"
  exit 1
fi
git push origin main || echo "⚠ no se pudo hacer push; hazlo luego: git push origin main"
echo "✅ main actualizado y desplegado en el puerto $HUB_PORT"
