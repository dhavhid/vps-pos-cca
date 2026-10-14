#!/usr/bin/env bash
# Copia los certificados Let's Encrypt y el dhparam del despliegue anterior de pos
# (${POS_BACKEND_DIR}/infra/ssl) a vps/, para no re-emitir los de sistemasrm.com.
#
#   scripts/migrate-from-pos.sh          # falla si vps/certbot/conf ya tiene certificados
#   scripts/migrate-from-pos.sh --force  # sobrescribe
source "$(dirname "$0")/lib.sh"

SRC="${POS_BACKEND_DIR:?falta POS_BACKEND_DIR}/infra/ssl"
DEST="$VPS_DIR/certbot/conf"

[ -d "$SRC/certbot/conf/live" ] || fail "No hay certificados en $SRC/certbot/conf/live"

if [ -d "$DEST/live" ] && [ -n "$(ls -A "$DEST/live" 2>/dev/null)" ] && [ "${1:-}" != "--force" ]; then
  fail "$DEST/live ya tiene contenido. Usa --force para sobrescribir."
fi

info "Copiando $SRC/certbot/conf -> $DEST"
mkdir -p "$DEST"
# -a conserva los symlinks live/ -> archive/ que certbot necesita para renovar.
cp -a "$SRC/certbot/conf/." "$DEST/"
ok "Certificados copiados: $(ls "$DEST/live" | grep -v README | tr '\n' ' ')"

if [ -f "$SRC/dhparam/dhparam.pem" ]; then
  mkdir -p "$VPS_DIR/nginx/dhparam"
  cp -a "$SRC/dhparam/dhparam.pem" "$VPS_DIR/nginx/dhparam/dhparam.pem"
  ok "dhparam copiado"
fi

# Los renewal/*.conf deben apuntar al webroot que monta edge_certbot.
if grep -L "webroot_path = /var/www/certbot" "$DEST"/renewal/*.conf 2>/dev/null | grep -q .; then
  echo -e "${YELLOW}Revisar: algunos renewal/*.conf no usan webroot /var/www/certbot:${NC}"
  grep -L "webroot_path = /var/www/certbot" "$DEST"/renewal/*.conf
fi
