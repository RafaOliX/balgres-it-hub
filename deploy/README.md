# Deploy — Balgres IT Hub

## Setup (una vez)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
sudo apt install -y git openssl

## Deploy
git clone --recurse-submodules git@github.com:RafaOliX/balgres-it-hub.git
cd balgres-it-hub
./scripts/setup-server.sh

## Actualizar
git pull && git submodule update --remote --merge
./scripts/setup-server.sh
