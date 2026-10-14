# Atajos de operación. Todos usan COMPOSE_FILE de .env (todos los stacks).
.PHONY: help config up down ps logs reload certs deploy-all deploy-nginx deploy-shared deploy-pos deploy-cca rebuild-web backup

help:
	@echo "make config        Valida y muestra el compose combinado"
	@echo "make up            Levanta todo (sin rebuild; usar deploy-* para builds)"
	@echo "make down          Detiene todo"
	@echo "make ps            Estado de los contenedores"
	@echo "make logs s=<svc>  Logs (todos o de un servicio)"
	@echo "make reload        nginx -t + reload"
	@echo "make certs         Emite certificados faltantes (scripts/init-ssl.sh)"
	@echo "make deploy-{all,nginx,shared,pos,cca}"
	@echo "make rebuild-web   Reconstruye cca_web con el contenido actual de Strapi"
	@echo "make backup        Respaldo de medios de Strapi"

config:
	docker compose config

up:
	docker compose up -d

down:
	docker compose down

ps:
	docker compose ps

logs:
	docker compose logs -f --tail=200 $(s)

reload:
	docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload

certs:
	scripts/init-ssl.sh

deploy-all:    ; scripts/deploy.sh all
deploy-nginx:  ; scripts/deploy.sh nginx
deploy-shared: ; scripts/deploy.sh shared
deploy-pos:    ; scripts/deploy.sh pos
deploy-cca:    ; scripts/deploy.sh cca
rebuild-web:   ; scripts/rebuild-web.sh
backup:        ; scripts/backup.sh
