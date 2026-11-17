# Instalación en Windows (pruebas / desarrollo)

Para producción usa Linux. En Windows se usa **Docker Desktop + WSL2**.

## 1. Requisitos
- Windows 10/11 actualizado con **WSL2** (`wsl --install` en PowerShell Admin) y una distro Ubuntu.
- **Docker Desktop** con la integración WSL activada para tu distro.
- Dentro de Ubuntu (WSL): `sudo apt install -y git openssl make`

## 2. Instalar (dentro de WSL, NO en PowerShell)
Clona en el sistema de archivos de Linux (`~/projects/...`), nunca en `/mnt/c/...` (lento y rompe permisos).

    mkdir -p ~/projects && cd ~/projects
    git clone git@github.com:RafaOliX/balgres-it-hub.git
    cd balgres-it-hub
    make setup

Abre `http://localhost:8091` en el navegador de Windows.

## 3. Entrar desde el móvil u otra PC de la red
Crea `C:\Users\TU_USUARIO\.wslconfig`:

    [wsl2]
    networkingMode=mirrored

Luego en PowerShell: `wsl --shutdown` y reinicia Docker Desktop. Con modo espejo no necesitas `portproxy`.
Si el móvil sigue sin cargar, abre el puerto (PowerShell **Admin**, cambia 8091 si usas otro):

    Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
    New-NetFirewallHyperVRule -Name "Balgres-8091" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 8091
    New-NetFirewallRule -DisplayName "Balgres-8091" -Direction Inbound -Protocol TCP -LocalPort 8091 -Action Allow -Profile Private

Desde el móvil: `http://IP-DE-LA-PC:8091` (la IP con `ipconfig` en Windows).

## 4. Detalles propios de Windows
- Los comandos `make ...` se ejecutan siempre dentro de WSL.
- Los backups quedan en `~/backups/` de WSL. Si borras la distro WSL los pierdes: copia a Windows:
  `rsync -av ~/backups/ /mnt/c/Users/TU_USUARIO/balgres-backups/`
- Docker Desktop debe estar abierto para que arranque el sistema.
- `flutter: command not found` en WSL: ver [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
