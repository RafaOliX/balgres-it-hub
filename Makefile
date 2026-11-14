.RECIPEPREFIX = >
# Uso: make <comando>.  Cada carpeta (main / pruebas) es su propia instancia.
.PHONY: setup up down logs ps backup restore deploy promote test doctor

setup:    ; ./scripts/setup-server.sh $(PORT) $(NAME)
up:       ; ./scripts/compose.sh up -d
down:     ; ./scripts/compose.sh down
logs:     ; ./scripts/compose.sh logs -f --tail=100 backend
ps:       ; ./scripts/compose.sh ps
backup:   ; ./scripts/backup.sh
restore:  ; ./scripts/restore.sh $(STAMP)
deploy:   ; ./scripts/deploy.sh
promote:  ; ./scripts/promote.sh
test:     ; ./scripts/test.sh
doctor:
> ./scripts/compose.sh exec -T backend curl -fsS http://localhost:8000/api/inventario/health && echo " OK"
