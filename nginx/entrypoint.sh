#!/bin/sh
# Arranque de edge_nginx: calcula los hostnames (DOMAIN_PREFIX) y delega en el entrypoint
# oficial, que renderiza /etc/nginx/templates/*.template -> /etc/nginx/conf.d con envsubst.
set -e
. /vps/hosts.sh

# Recarga periódica para tomar los certificados renovados por certbot
# (certbot no tiene acceso al socket de Docker para recargar nginx él mismo).
while :; do sleep 6h; nginx -s reload; done &

exec /docker-entrypoint.sh nginx -g "daemon off;"
