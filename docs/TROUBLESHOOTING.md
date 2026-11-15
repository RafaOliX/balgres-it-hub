# Problemas frecuentes

## Pantalla en blanco o versión vieja tras actualizar
Service Worker de Flutter. F12 → Application → Service Workers → Unregister → Clear site data → Ctrl+Shift+R.
Para confirmarlo, abre en incógnito.

## `setup` dice que el puerto está ocupado
    sudo ss -tlnp | grep ':8091 '
Para el otro servicio o cambia `HUB_PORT` en `.env.prod` y ejecuta `make up`.

## `setup` dice que existe el volumen pgdata pero no hay .env.prod
Ya hubo una instalación con esos datos y se perdió su `.env.prod`. Postgres ignora la contraseña nueva si el
volumen ya estaba inicializado, así que el backend no conectaría. Restaura el `env-*.prod` de tu backup como
`.env.prod`, o borra el volumen (**pierdes los datos**): `docker volume rm <instancia>_pgdata <instancia>_uploads`.

## No carga desde otra PC o el móvil
Firewall: `sudo ufw allow from 192.168.0.0/16 to any port 8091 proto tcp` (Linux). En Windows ver
[INSTALL-WINDOWS.md](INSTALL-WINDOWS.md). Usa `http://IP:PUERTO`, no `localhost`.

## No recuerdo la contraseña de admin
Si hay otro administrador, resetéala en Usuarios. Si no, la temporal inicial está en `make logs` (línea `[auth]`),
pero solo en el primer arranque.

## Caddy devuelve 308
`Caddyfile.prod` debe empezar exactamente con `:80 {`. Un dominio activa HTTPS automático y redirige a un puerto
443 que no está publicado.

## Backend: "no responde" tras `deploy`
    make logs
Los datos siguen intactos y el backup previo está en `~/backups/<instancia>/`.

## `flutter: command not found` en WSL
Flutter instalado con snap: `echo 'export PATH="$PATH:/snap/bin"' >> ~/.zshrc && source ~/.zshrc`.

## El build de Docker parece colgado en la imagen de Flutter
La primera vez descarga ~1,5 GB (5-10 min). Si falla por red, cambia en `docker/Dockerfile.web`
a `FROM subosito/flutter:stable AS build`.

## Docker ya se usa para otros proyectos
Cada instancia usa su propio nombre de proyecto y puerto, así que no choca por contenedores ni volúmenes.
Solo importa que `HUB_PORT` esté libre.

## Comandos útiles
    make ps | logs | doctor
    ./scripts/compose.sh exec db psql -U inventario inventario_it
