#!/usr/bin/env bash
# Despliega uno o todos los stacks. Hacer `git pull` en los repos antes.
#
#   scripts/deploy.sh all      # nginx + shared + pos + cca
#   scripts/deploy.sh nginx    # levanta/recarga nginx y certbot (tras cambiar nginx/)
#   scripts/deploy.sh shared   # rebuild + restart jasperservice
#   scripts/deploy.sh pos      # recrea pos_api y pos_static (compilan al arrancar)
#   scripts/deploy.sh cca      # rebuild cms + portal, espera al CMS público, rebuild web
#   scripts/deploy.sh web      # solo reconstruye cca_web (tras publicar contenido en Strapi)
source "$(dirname "$0")/lib.sh"

deploy_nginx() {
  info "nginx + certbot"
  dc up -d nginx certbot
  wait_healthy edge_nginx 60
  nginx_reload
}

deploy_shared() {
  info "Stack shared (jasperservice)"
  dc build jasperservice
  dc up -d jasperservice
  wait_healthy jasperservice 180
}

deploy_pos() {
  info "Stack pos"
  dc up -d --force-recreate pos_api pos_static
  wait_healthy pos_api 600
  wait_healthy pos_static 900
}

deploy_web() {
  # cca_web hornea el contenido de Strapi en build time desde la URL PÚBLICA del CMS.
  wait_url "${STRAPI_PUBLIC_URL:-https://cms-web.colegiaturas.com}/_health" 180
  info "Rebuild cca_web (--no-cache: el contenido viene de Strapi, Docker no ve el cambio)"
  dc build --no-cache cca_web
  dc up -d --no-deps cca_web
  ok "cca_web actualizado"
}

deploy_cca() {
  info "Stack cca"
  dc build cca_cms cca_portal
  dc up -d cca_cms cca_portal
  wait_healthy cca_cms 300
  wait_healthy cca_portal 120
  deploy_web
}

case "${1:-}" in
  all)    deploy_nginx; deploy_shared; deploy_pos; deploy_cca ;;
  nginx)  deploy_nginx ;;
  shared) deploy_shared ;;
  pos)    deploy_pos ;;
  cca)    deploy_cca ;;
  web)    deploy_web ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
