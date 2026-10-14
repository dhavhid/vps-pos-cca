# secrets/

No se versiona (salvo este README).

- `do-postgres-ca.crt`: CA del cluster Postgres de DigitalOcean.
  Panel DO → Databases → cluster → *Connection details* → **Download CA certificate**.
  Se monta en cca_cms y cca_portal como `/certs/do-postgres-ca.crt` (`NODE_EXTRA_CA_CERTS`).
