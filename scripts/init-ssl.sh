#!/usr/bin/env bash
# Prepara TLS para todos los dominios. Idempotente: solo emite lo que falta.
#
#   scripts/init-ssl.sh                 # todos los lineages sin certificado real
#   scripts/init-ssl.sh web.colegiaturas.com   # solo ese lineage
#   STAGING=1 scripts/init-ssl.sh       # prueba contra Let's Encrypt staging
#
# Pasos: dhparam -> certificados dummy (para que nginx arranque) -> nginx up ->
#        certbot certonly --webroot por lineage -> reload.
# Requiere que el DNS de cada dominio ya apunte a este servidor.
source "$(dirname "$0")/lib.sh"

# lineage=dominio1,dominio2,...  (el lineage es el nombre en certbot/conf/live/)
LINEAGES=(
  "sistemasrm.com=sistemasrm.com,www.sistemasrm.com"
  "pos.sistemasrm.com=pos.sistemasrm.com"
  "posapi.sistemasrm.com=posapi.sistemasrm.com"
  "colegiaturas.com=colegiaturas.com,www.colegiaturas.com"
  "web.colegiaturas.com=web.colegiaturas.com"
  "cms-web.colegiaturas.com=cms-web.colegiaturas.com"
  "portal-padres.colegiaturas.com=portal-padres.colegiaturas.com"
)

: "${LE_EMAIL:?falta LE_EMAIL en .env}"
CONF="$VPS_DIR/certbot/conf"
mkdir -p "$CONF" "$VPS_DIR/certbot/www" "$VPS_DIR/nginx/dhparam"

has_real_cert() { [ -f "$CONF/renewal/$1.conf" ]; }

make_dummy() {
  local name="$1" dir="$CONF/live/$1"
  mkdir -p "$dir"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$dir/privkey.pem" -out "$dir/fullchain.pem" -subj "/CN=$name" 2>/dev/null
  cp "$dir/fullchain.pem" "$dir/chain.pem"
}

# 1. dhparam
if [ ! -f nginx/dhparam/dhparam.pem ]; then
  info "Generando dhparam (tarda unos minutos)..."
  openssl dhparam -out nginx/dhparam/dhparam.pem 2048
fi
ok "dhparam listo"

# 2. Selección de lineages
selected=()
for entry in "${LINEAGES[@]}"; do
  name="${entry%%=*}"
  if [ $# -gt 0 ] && [[ ! " $* " =~ " $name " ]]; then continue; fi
  selected+=("$entry")
done
[ ${#selected[@]} -gt 0 ] || fail "Ningún lineage coincide con: $*"

# 3. Dummies para los que no tienen certificado (nginx no arranca sin los archivos)
pending=()
for entry in "${selected[@]}"; do
  name="${entry%%=*}"
  if has_real_cert "$name"; then
    ok "$name ya tiene certificado real"
  else
    [ -f "$CONF/live/$name/fullchain.pem" ] || make_dummy "$name"
    pending+=("$entry")
  fi
done

# 4. nginx arriba con lo que haya
dc up -d nginx certbot
wait_healthy edge_nginx 60
nginx_reload

# 5. Emisión real
staging_flag=()
[ "${STAGING:-0}" = "1" ] && staging_flag=(--staging)

for entry in ${pending[@]+"${pending[@]}"}; do
  name="${entry%%=*}"
  IFS=',' read -r -a domains <<< "${entry#*=}"
  dargs=(); for d in "${domains[@]}"; do dargs+=(-d "$d"); done

  info "Emitiendo $name (${domains[*]})"
  rm -rf "$CONF/live/$name"   # quitar el dummy: certbot exige que no exista
  if dc run --rm --entrypoint certbot certbot certonly \
      --webroot -w /var/www/certbot --cert-name "$name" "${dargs[@]}" \
      --email "$LE_EMAIL" --agree-tos --no-eff-email --non-interactive \
      ${staging_flag[@]+"${staging_flag[@]}"}; then
    ok "$name emitido"
  else
    echo -e "${RED}✗ Falló $name — se restaura el dummy. Revisar DNS y reintentar:${NC} scripts/init-ssl.sh $name" >&2
    make_dummy "$name"
  fi
done

nginx_reload
ok "TLS listo. Renovación: contenedor edge_certbot (12h) + reload de nginx (6h)."
