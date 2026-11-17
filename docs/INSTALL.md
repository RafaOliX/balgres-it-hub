# Instalación en Linux / servidor

## 1. Requisitos
- Linux (Ubuntu/Debian probado) con **Docker + Compose v2**, **git** y **openssl**.
- Un puerto libre (por defecto **8091**).

    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER      # cierra sesión y vuelve a entrar
    sudo apt install -y git openssl make

## 2. Instalar

    git clone git@github.com:RafaOliX/balgres-it-hub.git
    cd balgres-it-hub
    git checkout main          # producción. Usa develop solo para pruebas
    make setup

`make setup` hace todo: genera `.env.prod` con claves aleatorias (no copies el de otra PC),
compila (la primera vez tarda ~10 min por el SDK de Flutter), levanta el stack, espera a que
el backend responda e imprime la contraseña inicial.

Otro puerto: `make setup PORT=9000`.

## 3. Primer login
Abre `http://IP-DEL-SERVIDOR:8091`, usuario `admin` y la contraseña temporal que imprimió `setup`.
El sistema obliga a cambiarla. Luego crea usuarios reales en **Usuarios** y asígnales rol
(Administrador, Técnico, Consulta o uno propio).

¿Se perdió la contraseña temporal? `make logs` y busca la línea `[auth]` (solo existe en el primer arranque).

## 4. Abrir el firewall
Solo el puerto de la app, y solo para tu red:

    sudo ufw allow from 192.168.0.0/16 to any port 8091 proto tcp
    sudo ufw enable

## 5. Backup automático (hazlo el día 1)
`make deploy` respalda al actualizar, pero no es un plan de backup. Cron diario:

    crontab -e
    0 3 * * * cd /RUTA/AL/balgres-it-hub && ./scripts/backup.sh >> $HOME/backups/cron.log 2>&1

Copia `~/backups/` fuera del servidor con regularidad (ver [BACKUP.md](BACKUP.md)).

## 6. Actualizar
    cd balgres-it-hub
    git pull
    make deploy

## Lo que NO incluye (pendiente, decide antes de exponerlo fuera de la LAN)
- **HTTPS/dominio.** Hoy se sirve por HTTP en el puerto elegido, y el token de sesión viaja sin cifrar.
  En una red interna de confianza es aceptable; fuera de ella no. Poner un dominio en `Caddyfile.prod`
  no basta (el compose no publica 80/443): es un cambio aparte.
- **Datos sensibles en "datos técnicos".** No guardes contraseñas de routers u otros equipos en esos campos:
  los devuelve el listado de inventario a cualquier usuario con permiso `inventario.ver`.
- **Módulo Redes:** el servidor debe estar en la misma red que los segmentos que va a escanear.
  Si no quieres escaneos automáticos, pon `REDES_PING_MINUTES=0` en `.env.prod` y `make up`.
