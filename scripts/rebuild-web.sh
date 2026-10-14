#!/usr/bin/env bash
# Reconstruye el sitio público (cca_web) con el contenido actual de Strapi.
# Pensado para cron o un webhook de Strapi, p. ej. cada hora:
#   0 * * * * /vps/scripts/rebuild-web.sh >> /var/log/cca-web-rebuild.log 2>&1
exec "$(dirname "$0")/deploy.sh" web
