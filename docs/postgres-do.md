# Postgres en DigitalOcean

Todas las apps del VPS usan el cluster administrado. No hay contenedores de base de datos.

| Consumidor | Base | Usuario | Notas |
|---|---|---|---|
| `pos_api` | la de pos (hoy `defaultdb`) | hoy `doadmin` | configurado en `/pos-backend/.env.production` |
| `jasperservice` | la de pos | `stacks/shared/jasper.env` | recomendado: usuario de solo lectura |
| `cca_cms` (Strapi) | `cca_cms`, esquema `public` | `postgres` | `stacks/cca/cms.env` |
| `cca_portal` | base del colegio (tablas `cca_*`) | `portal_user` | `stacks/cca/portal.env` — la migración de esta base la hace el dueño del proyecto |

> **Seguridad:** `pos_api` usa hoy `doadmin` (superusuario del cluster). Conviene migrarlo a un
> usuario dedicado con permisos solo sobre su base.

## 1. Trusted sources

Panel DO → Databases → cluster → *Settings* → **Trusted Sources**: agregar la IP del VPS.
Sin esto las conexiones se cortan con timeout.

## 2. CA del cluster

*Connection details* → **Download CA certificate** → guardar como `vps/secrets/do-postgres-ca.crt`.
Se monta en `cca_cms` y `cca_portal` con `NODE_EXTRA_CA_CERTS`, lo que permite verificar TLS
(`DATABASE_SSL_REJECT_UNAUTHORIZED=true` en Strapi y `sslmode=verify-full` en el portal).

## 3. Strapi: base

Strapi usa el esquema `public` de su propia base `cca_cms`, con el usuario `postgres`.
En el panel: *Users & Databases* → crear base **`cca_cms`**.

### Restaurar el contenido

```bash
psql "postgresql://postgres:<pw>@<host>:25060/cca_cms?sslmode=require" -f <dump>.sql
psql "...cca_cms..." -c "select count(*) from information_schema.tables where table_schema='public';"
```

- Si el dump empieza con `\restrict` (pg_dump ≥ 16.10), usar un **psql 16.10+ / 17.6+**.
- Usar en `cms.env` los **mismos** `APP_KEYS`, `ENCRYPTION_KEY`, `*_SALT`, `*_SECRET` que el
  entorno de origen (`cca/.env`), o se invalidan tokens de API y sesiones.
- Los **archivos** de medios (imágenes/PDFs) no están en el dump: viven en el volumen
  `cms_uploads`. Ver `docs/migracion.md` §0.

## 4. Portal Familiar

Usuario `portal_user` sobre la base del colegio, sin DDL ni DELETE
(detalle en `cca/docs/portal-datos.md`):

```sql
GRANT CONNECT ON DATABASE <base_colegio> TO portal_user;
GRANT USAGE ON SCHEMA public TO portal_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO portal_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO portal_user;
```

## 5. Presupuesto de conexiones

Los clusters chicos de DO tienen pocas conexiones (≈ 22 por GB de RAM, menos 3 reservadas).
Ver el límite real en *Connection details* → `max_connections`.

| Servicio | Pool máx. | Dónde se ajusta |
|---|---|---|
| `cca_cms` | 5 | `DATABASE_POOL_MAX` en `cms.env` |
| `cca_portal` | 10 | default de TypeORM/pg (no configurable por env hoy) |
| `pos_api` | según su config | `/pos-backend` |
| `jasperservice` | según su config | código de jasper |

Si la suma se acerca al límite: crear **Connection Pools** en DO (PgBouncer, puerto `25061`,
modo *transaction*) y apuntar ahí `pos_api`, `cca_portal` y `jasperservice`. Strapi conviene
dejarlo directo (`25060`): sus migraciones (Knex) no funcionan bien en modo transaction.

## 6. Verificar desde el VPS

```bash
docker run --rm -v "$PWD/secrets:/certs:ro" postgres:16-alpine \
  psql "postgresql://postgres:<pw>@<host>:25060/cca_cms?sslmode=verify-full&sslrootcert=/certs/do-postgres-ca.crt" \
  -c "select current_user, current_schema();"
```
Repetir con `portal_user` y el usuario de jasper.
