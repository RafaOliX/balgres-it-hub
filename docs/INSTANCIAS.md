# Instancias, puertos y promoción develop → main

Cada carpeta del repo es una instancia independiente (contenedores, DB y fotos propios).
Lo que la distingue es su `.env.prod`: `COMPOSE_PROJECT_NAME` (nombre) y `HUB_PORT` (puerto).

## Instalar la principal (main)
    git clone git@github.com:RafaOliX/balgres-it-hub.git && cd balgres-it-hub
    git checkout main
    make setup                      # puerto 8091 por defecto
    # otro puerto:  make setup PORT=9000

## Añadir una instancia de pruebas en la misma PC (rama develop)
    git worktree add ../balgres-it-hub-test develop
    cd ../balgres-it-hub-test
    make setup PORT=8092 NAME=balgres-it-hub-test

Abre http://localhost:8092. Tiene su propia base de datos y no toca la principal.
(Una rama solo puede estar abierta en una carpeta: main en la principal, develop en la de pruebas.)

## Cambiar el puerto de una instancia ya creada
Edita `HUB_PORT` en su `.env.prod` y ejecuta `make up`.

## Probar con datos reales
    cd ~/projects/balgres-it-hub && make backup          # anota el STAMP
    cd ~/projects/balgres-it-hub-test
    BACKUP_DIR=$HOME/backups/balgres-it-hub make restore STAMP=<STAMP>

## Flujo de trabajo diario
1. En la carpeta de pruebas (develop): programar, `git commit`, `make deploy`, probar en :8092.
2. Cuando esté probado, en la carpeta principal: `make promote`.
   Muestra los commits, pide confirmación, hace merge develop → main, backup, build, levanta y espera salud.
3. Si falla, el script imprime el comando exacto para volver al código anterior.

## Backups y restore
    make backup                 # guarda en ~/backups/<nombre-instancia>/
    make restore STAMP=YYYYMMDD-HHMM
Cada instancia usa su propia carpeta de backups. Copia `~/backups` fuera de la PC con regularidad.

## Comandos útiles
    make ps | logs | up | down | doctor
