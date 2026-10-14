# vps — infraestructura unificada

Un solo VPS, un solo `docker compose`, un solo nginx con certbot al frente de todos los proyectos.
Postgres **no** corre aquí: todas las apps usan el cluster administrado de DigitalOcean.

```
                   Internet :80/:443
                          │
                 ┌────────▼────────┐   edge_certbot (renew 12h)
                 │   edge_nginx    │◄─────────────
                 └───┬─────────┬───┘
       red vps_edge  │         │
   ┌─────────────────┘         └──────────────────┐
   │ sistemasrm.com                                │ colegiaturas.com
   │  apex / www → website estático               │  apex / www     → mantenimiento
   │  pos.       → pos_static:3001                 │  web.           → cca_web:80
   │  posapi.    → pos_api:3000                    │  cms-web.       → cca_cms:1337
   │                                               │  portal-padres. → cca_portal:3000
   └──────────┬────────────────────────────────────┴──────┬─────────┘
              │         red vps_services (interna)         │
              └─────────► jasperservice:8080 ◄─────────────┘
                                  │
                   Postgres DigitalOcean (TLS, :25060)
```

Todos los hostnames llevan el prefijo `DOMAIN_PREFIX` (ver [Stage vs producción](#stage-vs-producción)).

Solo `edge_nginx` publica puertos. `jasperservice` es interno: cualquier contenedor en la red
`services` lo alcanza en `http://jasperservice:8080`.

## Estructura

| Ruta | Contenido |
|---|---|
| `compose.yml` | nginx, certbot, redes |
| `stacks/shared/` | `jasperservice` (build desde `/pos-backend/services/jasperservice`) |
| `stacks/pos/` | `pos_api` (`/pos-backend`), `pos_static` (`/pos-frontend`) |
| `stacks/cca/` | `cca_cms`, `cca_web`, `cca_portal` (build desde `/cca`) |
| `nginx/` | `nginx.conf`, `snippets/`, `templates/` (una plantilla por dominio), `entrypoint.sh` |
| `static/colegiaturas/` | placeholder de mantenimiento de colegiaturas.com |
| `scripts/` | `hosts.sh` (hostnames según `DOMAIN_PREFIX`), `deploy.sh`, `init-ssl.sh`, `migrate-from-pos.sh`, `rebuild-web.sh`, `backup.sh` |
| `docs/` | `migracion.md` (corte desde el despliegue actual de pos), `postgres-do.md` |

El website de sistemasrm.com se sirve directo desde el repo de pos (`/pos-backend/infra/website`).

Los stacks se combinan con `COMPOSE_FILE` en `.env`, así que cualquier `docker compose ...`
ejecutado en este directorio opera sobre todos.

## Configuración

```bash
cp .env.example .env                                   # DOMAIN_PREFIX, rutas a repos, email LE
cp stacks/shared/jasper.env.example stacks/shared/jasper.env
cp stacks/pos/pos.env.example       stacks/pos/pos.env  # opcional (JASPER_URL)
cp stacks/cca/cms.env.example       stacks/cca/cms.env
cp stacks/cca/portal.env.example    stacks/cca/portal.env
# CA del cluster DO -> secrets/do-postgres-ca.crt (ver secrets/README.md)
docker compose config >/dev/null && echo OK
```

`pos_api` y `pos_static` siguen leyendo `/pos-backend/.env.production` como antes.
`EXPO_PUBLIC_API_URL` (pos_static) y `PORTAL_PUBLIC_URL` (cca_portal) los fija compose según
`DOMAIN_PREFIX`.

## Stage vs producción

Un solo valor en `.env` decide todos los hostnames públicos (nginx, certificados, URLs horneadas
en los builds). Regla: subdominio = `${DOMAIN_PREFIX}<sub>`, apex = `${DOMAIN_PREFIX}.<dominio>`.

| Servicio | `DOMAIN_PREFIX=stage` | `DOMAIN_PREFIX=` (producción) |
|---|---|---|
| Website SRM | stage.sistemasrm.com | sistemasrm.com |
| www SRM (301) | stagewww.sistemasrm.com | www.sistemasrm.com |
| POS frontend | stagepos.sistemasrm.com | pos.sistemasrm.com |
| POS API | stageposapi.sistemasrm.com | posapi.sistemasrm.com |
| CCA mantenimiento | stage.colegiaturas.com | colegiaturas.com |
| www CCA | stagewww.colegiaturas.com | www.colegiaturas.com |
| CCA web | stageweb.colegiaturas.com | web.colegiaturas.com |
| CCA CMS | stagecms-web.colegiaturas.com | cms-web.colegiaturas.com |
| Portal Familiar | stageportal-padres.colegiaturas.com | portal-padres.colegiaturas.com |

Ver los hostnames efectivos: `set -a; . ./.env; . scripts/hosts.sh; env | grep -E '^(SRM|CCA)_'`.

Pasar a producción:
1. DNS de los hostnames de producción → IP de este VPS.
2. `.env`: `DOMAIN_PREFIX=` (vacío).
3. `scripts/init-ssl.sh` (emite los certificados de los hostnames nuevos; los de stage quedan sin uso).
4. `scripts/deploy.sh all` (recrea nginx con las plantillas nuevas y reconstruye pos_static/cca_web
   con las URLs nuevas).

## Operación diaria

| Tarea | Comando |
|---|---|
| Desplegar un stack (tras `git pull` en su repo) | `scripts/deploy.sh pos\|cca\|shared` |
| Cambié algo en `nginx/` | `scripts/deploy.sh nginx` |
| Publiqué contenido en Strapi | `scripts/rebuild-web.sh` |
| Nuevo dominio / certificado faltante | hostname en `scripts/hosts.sh` + `LINEAGES` en `scripts/init-ssl.sh` → `scripts/init-ssl.sh <lineage>` |
| Logs | `make logs s=cca_portal` |
| Respaldo de medios de Strapi | `scripts/backup.sh` |

Notas:
- `cca_web` hornea el contenido de Strapi **en build time** desde la URL pública del CMS, así que el CMS
  debe estar público (DNS + certificado) antes de construirlo. `deploy.sh cca` espera a que lo esté.
- nginx resuelve los upstreams en cada request (`resolver 127.0.0.11` + `set $upstream`): si un
  stack está caído, nginx arranca igual y los demás sitios siguen funcionando (ese sitio da 502).
- Certificados: `edge_certbot` intenta renovar cada 12h; `edge_nginx` se recarga cada 6h para
  tomarlos. Verificar con `docker compose run --rm --entrypoint certbot certbot renew --dry-run`.

## Agregar un proyecto nuevo

1. `stacks/<nuevo>/compose.yml` con sus servicios en la red `edge` (y `services` si usa jasper).
2. Añadirlo a `COMPOSE_FILE` en `.env`.
3. Hostnames en `scripts/hosts.sh` (con `DOMAIN_PREFIX`) y en `NGINX_ENVSUBST_FILTER` de
   `compose.yml` si usan un prefijo de variable nuevo.
4. `nginx/templates/<dominio>.conf.template` siguiendo las existentes.
5. Lineage nuevo en `scripts/init-ssl.sh`, luego `scripts/init-ssl.sh <lineage>`.
