#!/usr/bin/env bash
set -euo pipefail

# ---- Defaults setzen (weil envsubst keine ${VAR:-default} Syntax versteht)
: "${PSQL_PORT:=5432}"
: "${ODOO_WORKERS:=2}"

# ---- Pflicht-Variablen prüfen
missing=0
for v in PSQL_IP ODOO_DB_USER ODOO_DB_PASS ODOO_ADMIN_PASS; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: Environment variable $v is not set!" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "Abbruch: bitte fehlende Variablen setzen (z.B. via env_file)." >&2
  exit 1
fi

# ---- Config aus Template erzeugen
envsubst < /etc/odoo/odoo.conf.template > /etc/odoo/odoo.conf
echo "Generated /etc/odoo/odoo.conf:"
head -n 20 /etc/odoo/odoo.conf || true

# ---- venv aktivieren + PATH
. /opt/odoo/venv/bin/activate
export PATH="/opt/odoo/venv/bin:${PATH}"

# ---- Standardkommando: Odoo starten
if [ "$#" -eq 0 ]; then
  set -- python /opt/odoo/src/odoo-bin -c /etc/odoo/odoo.conf
fi

exec "$@"
