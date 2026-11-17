# Balgres IT Hub

Plataforma modular de herramientas internas del departamento de IT de Balgres.
Módulos: **Inventario**, **Empleados (contacts)** y **Redes**.



Stack: Flutter (Web/Android) · FastAPI + SQLModel · PostgreSQL 16 · Caddy · Docker Compose.

## Instalar (Linux o WSL2, 3 comandos)

    git clone git@github.com:RafaOliX/balgres-it-hub.git
    cd balgres-it-hub
    make setup

Al terminar imprime la URL (`http://localhost:8091`), el usuario `admin` y su contraseña temporal.
Solo necesitas Docker + Compose v2, git y openssl.

## Comandos diarios

    make up | down | ps | logs | doctor
    make backup
    make restore STAMP=YYYYMMDD-HHMM
    make deploy       # actualizar esta instancia (hace backup antes)
    make promote      # develop -> main + deploy (en la carpeta de main)
    make test

## Documentación

| Quiero... | Documento |
|---|---|
| Instalar en Linux / servidor | [docs/INSTALL.md](docs/INSTALL.md) |
| Instalar en Windows | [docs/INSTALL-WINDOWS.md](docs/INSTALL-WINDOWS.md) |
| Backups, restaurar, migrar a otra PC | [docs/BACKUP.md](docs/BACKUP.md) |
| Dos instancias (principal + pruebas) y pasar develop a main | [docs/INSTANCIAS.md](docs/INSTANCIAS.md) |
| Desarrollar, tests, ramas, añadir módulos | [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |
| Algo no funciona | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Ramas

`develop` = integración (todo el trabajo nuevo). `main` = producción (solo merge desde develop).
Commits con prefijo: `[hub] [inventario] [contacts] [redes] [auth] [scripts] [docs]`.
