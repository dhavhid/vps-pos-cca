# Funciones comunes. Uso: source "$(dirname "$0")/lib.sh"
set -euo pipefail

VPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VPS_DIR"

if [ ! -f .env ]; then
  echo "Falta $VPS_DIR/.env (cp .env.example .env)" >&2
  exit 1
fi
set -a; . ./.env; set +a
# SRM_* / CCA_*: hostnames públicos según DOMAIN_PREFIX.
. "$VPS_DIR/scripts/hosts.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${YELLOW}==> $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

dc() { docker compose "$@"; }

# wait_healthy <contenedor> [segundos]
wait_healthy() {
  local name="$1" timeout="${2:-300}" status
  info "Esperando a que $name esté healthy (máx ${timeout}s)..."
  for _ in $(seq 1 "$timeout"); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || true)"
    case "$status" in
      healthy|running) ok "$name: $status"; return 0 ;;
      unhealthy|exited|dead) fail "$name: $status — revisar: docker compose logs $name" ;;
    esac
    sleep 1
  done
  fail "$name no quedó healthy a tiempo — revisar: docker compose logs $name"
}

# wait_url <url> [segundos]
wait_url() {
  local url="$1" timeout="${2:-180}"
  info "Esperando $url (máx ${timeout}s)..."
  for _ in $(seq 1 "$((timeout / 3))"); do
    curl -fsS -o /dev/null "$url" && { ok "$url responde"; return 0; }
    sleep 3
  done
  fail "$url no respondió a tiempo"
}

nginx_reload() {
  dc exec -T nginx nginx -t
  dc exec -T nginx nginx -s reload
  ok "nginx recargado"
}
