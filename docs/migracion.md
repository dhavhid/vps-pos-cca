# Migración al VPS unificado

Estado actual del VPS: pos corre con `/pos-backend/infra/docker-compose.yml` (nginx propio en 80/443).
Objetivo: reemplazarlo por `vps/` y sumar cca, con una caída de solo segundos para pos.

Rutas asumidas en el VPS (configurables en `.env`):

```
/pos-backend    repo backend de pos   (POS_BACKEND_DIR)
/pos-frontend   repo frontend de pos  (POS_FRONTEND_DIR)
/cca            repo cca              (CCA_DIR)
/vps            este proyecto
```

## 0. Antes del día del corte

1. **DNS** (registros A → IP del VPS):
   `colegiaturas.com`, `www.colegiaturas.com`, `web.colegiaturas.com`,
   `cms-web.colegiaturas.com`, `portal-padres.colegiaturas.com`.
   Verificar: `dig +short cms-web.colegiaturas.com`.
2. **Postgres DO**: seguir `docs/postgres-do.md` §1–§4 (trusted sources, CA, base y usuario de
   Strapi, restaurar `strapi-cms-20261012.sql`, usuario del portal). La base del colegio la
   migra el dueño del proyecto.
3. **Medios de Strapi** (no están en el dump SQL). Desde la máquina donde está el volumen actual:
   ```bash
   docker run --rm -v cca_cms_uploads:/data:ro -v "$PWD":/backup alpine \
     tar czf /backup/cms_uploads.tar.gz -C /data .
   scp cms_uploads.tar.gz vps:/tmp/
   ```
4. **Clonar** en el VPS: `/cca` y `/vps`. Docker Compose ≥ v2.24 (`docker compose version`).
5. **Configurar** `vps/.env`, `stacks/*/*.env` y `secrets/do-postgres-ca.crt` (ver README).
   `cms.env` debe usar los mismos secretos de Strapi que `cca/.env`.
6. **Validar**: `docker compose config >/dev/null && echo OK`.
7. **Pre-construir** imágenes (no afecta a lo que corre):
   ```bash
   docker compose build jasperservice cca_cms cca_portal
   docker compose pull nginx certbot
   ```
8. **Restaurar medios** en el volumen nuevo: `scripts/backup.sh restore /tmp/cms_uploads.tar.gz`.

## 1. Corte (pos fuera unos segundos)

```bash
cd /vps
scripts/migrate-from-pos.sh                # copia certificados + dhparam de pos

# Parar el stack viejo (libera 80/443 y los nombres de contenedor)
docker compose -f /pos-backend/infra/docker-compose.yml down

scripts/init-ssl.sh                        # dummies faltantes + nginx/certbot arriba + emite colegiaturas.com
                                           # (sistemasrm.com ya viene migrado; nginx no arranca sin todos los certs)
scripts/deploy.sh shared                   # jasperservice
scripts/deploy.sh pos                      # pos_api + pos_static (compilan al arrancar: varios minutos)
```

`pos_api` y `pos_static` compilan al arrancar igual que antes, así que pos.sistemasrm.com y
posapi.sistemasrm.com devuelven 502 hasta que terminan. Para reducir esa ventana, levantar pos
primero y luego el resto: el orden de arriba ya lo hace.

## 2. CCA

```bash
scripts/deploy.sh cca     # build cms + portal, espera https://cms-web.colegiaturas.com/_health, build web
```

Si es el primer arranque del CMS sin datos restaurados: entrar a
`https://cms-web.colegiaturas.com/admin`, crear el admin, cargar contenido y luego
`scripts/rebuild-web.sh`.

## 3. Verificación

```bash
for u in sistemasrm.com www.sistemasrm.com pos.sistemasrm.com posapi.sistemasrm.com/health \
         colegiaturas.com web.colegiaturas.com cms-web.colegiaturas.com/_health \
         portal-padres.colegiaturas.com; do
  printf '%-45s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://$u")"
done
curl -s -o /dev/null -w '%{http_code}\n' https://portal-padres.colegiaturas.com/api/health  # 404 esperado

docker compose ps
docker compose run --rm --entrypoint certbot certbot renew --dry-run
docker compose exec pos_api wget -qO- http://jasperservice:8080/health   # jasper interno
curl -m 5 http://<IP_VPS>:8080 || echo "OK: jasper no expuesto"
```

## 4. Rollback

```bash
cd /vps && docker compose down
docker compose -f /pos-backend/infra/docker-compose.yml up -d
```
Los certificados originales de pos quedan intactos en `/pos-backend/infra/ssl` (se copiaron, no se movieron).

## 5. Después

- Cron: `scripts/backup.sh` (diario) y, si se quiere, `scripts/rebuild-web.sh` (o webhook de Strapi).
- Firewall: solo 22, 80, 443 abiertos (`ufw allow OpenSSH && ufw allow 80,443/tcp`).
  Ojo: Docker se salta ufw para puertos publicados; aquí solo nginx publica puertos.
- Recomendado en `cca/apps/cms/config/server.js`: `url: env('PUBLIC_URL')` y `proxy: true`
  (cookies seguras del admin y URLs absolutas de medios detrás de nginx).
- Recomendado en pos: Dockerfiles multi-stage para `pos_api`/`pos_static` en lugar de compilar
  al arrancar, y un usuario de base dedicado en lugar de `doadmin`.
