# Backups, restauración y migración

Cada instancia guarda en `~/backups/<nombre-instancia>/` (principal: `~/backups/balgres-it-hub/`).

## Crear un backup
    make backup

Genera 4 archivos con el mismo sello `STAMP` (`YYYYMMDD-HHMM`):

| Archivo | Contenido |
|---|---|
| `db-STAMP.sql.gz` | Base de datos completa (incluye usuarios, roles y hashes; **no** las sesiones abiertas) |
| `uploads-STAMP.tar.gz` | Fotos de los activos |
| `env-STAMP.prod` | `.env.prod` (contiene secretos, permisos 600) |
| `sums-STAMP.txt` | Checksums SHA-256 de los tres anteriores |

Antes de dar OK valida que el dump no esté vacío, sea gzip válido y traiga las tablas esperadas.
Si algo falla, borra los archivos parciales y aborta.

## Restaurar
    make restore                      # sin STAMP lista los backups disponibles
    make restore STAMP=20261112-1550

Valida checksums y contenido antes de tocar nada, pide confirmación, **crea un backup de seguridad**
(`db-pre-restore-*.sql.gz`), restaura la DB en una sola transacción (si falla, se revierte), reemplaza las fotos
y levanta el backend. Al final imprime cómo deshacer.

## Migrar a otra PC
1. Origen: `make backup`.
2. Copia `db-*`, `uploads-*`, `sums-*` y `env-*` del STAMP a `~/backups/balgres-it-hub/` del destino (`scp`/`rsync`/USB).
3. Destino: instala (`make setup`, ver [INSTALL.md](INSTALL.md)) y luego `make restore STAMP=...`.
4. Entra con el `admin` **del origen**: el restore trae sus usuarios y contraseñas.

No copies el `.env.prod` de otra PC encima del nuevo: las claves de Postgres/JWT del destino son suyas y
no viajan en el dump. `env-*.prod` es solo para recuperar la misma instancia tras un desastre.

## Copiar datos de producción a la instancia de pruebas
    cd <carpeta-de-pruebas>
    BACKUP_DIR=$HOME/backups/balgres-it-hub make restore STAMP=<STAMP>

## Verificar tras restaurar
- `make doctor` responde OK.
- Abre la app: activos con fotos, Empleados con datos, Dashboard con conteos distintos de cero.
- Inicia sesión.

## Automatizar y retención
Cron diario: ver [INSTALL.md](INSTALL.md#5-backup-automático-hazlo-el-día-1).
El script **no borra** backups viejos. Política sugerida (30 días, conserva los pre-restore):

    find ~/backups/balgres-it-hub -type f \( -name 'db-2*' -o -name 'uploads-*' -o -name 'env-*' -o -name 'sums-*' \) -mtime +30 -delete

**Copia externa obligatoria:** si el disco o la distro WSL desaparece, los backups también.
No borres nada sin una copia externa verificada.
