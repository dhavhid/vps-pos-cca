#!/usr/bin/env bash
# Respaldo de los medios de Strapi (volumen vps_cms_uploads). La base de datos la
# respalda DigitalOcean (backups diarios del cluster administrado).
#
#   scripts/backup.sh                    # crea backups/cms_uploads-<fecha>.tar.gz (guarda los últimos 14)
#   scripts/backup.sh restore <archivo>  # restaura un tar.gz en el volumen (detén cca_cms antes)
#
# Copiar backups/ fuera del VPS (rclone, rsync, Spaces...). Cron sugerido:
#   30 3 * * * /vps/scripts/backup.sh >> /var/log/vps-backup.log 2>&1
source "$(dirname "$0")/lib.sh"

VOLUME="${COMPOSE_PROJECT_NAME:-vps}_cms_uploads"
BACKUP_DIR="$VPS_DIR/backups"
KEEP=14
mkdir -p "$BACKUP_DIR"

case "${1:-}" in
  restore)
    file="$(cd "$(dirname "${2:?falta archivo}")" && pwd)/$(basename "$2")"
    [ -f "$file" ] || fail "No existe $file"
    docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null
    info "Restaurando $file en $VOLUME"
    docker run --rm -v "$VOLUME":/data -v "$(dirname "$file")":/backup:ro alpine \
      sh -c "tar xzf /backup/$(basename "$file") -C /data && chown -R 1000:1000 /data"
    ok "Restaurado. Levantar: docker compose up -d cca_cms"
    ;;
  "")
    out="cms_uploads-$(date +%Y%m%d-%H%M%S).tar.gz"
    info "Respaldando $VOLUME -> backups/$out"
    docker run --rm -v "$VOLUME":/data:ro -v "$BACKUP_DIR":/backup alpine \
      tar czf "/backup/$out" -C /data .
    ls -1t "$BACKUP_DIR"/cms_uploads-*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
    ok "backups/$out"
    ;;
  *) fail "Uso: $0 [restore <archivo>]" ;;
esac
