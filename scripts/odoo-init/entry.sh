#!/usr/bin/env bash
set -euo pipefail

echo "[entry] starting init for Odoo ${ODOO_VERSION:-18.0}"
echo "[entry] DB_HOST=${DB_HOST:-db} DB_PORT=${DB_PORT:-5432} DB_USER=${DB_USER:-odoo} DESIRED_DB=${DESIRED_DB:-${COMPOSE_PROJECT_NAME}_db}"

# wait for postgres
until PGPASSWORD="${DB_PASSWORD:-password}" psql -h "${DB_HOST:-db}" -U "${DB_USER:-odoo}" -p "${DB_PORT:-5432}" -d postgres -c "select 1" >/dev/null 2>&1; do
  echo "[entry] waiting for postgres ${DB_HOST:-db}:${DB_PORT:-5432} ..."
  sleep 2
done
echo "[entry] postgres is reachable"

DB_NAME="${DESIRED_DB:-${COMPOSE_PROJECT_NAME}_db}"
export PGHOST="${DB_HOST:-db}"
export PGPORT="${DB_PORT:-5432}"
export PGUSER="${DB_USER:-odoo}"
export PGPASSWORD="${DB_PASSWORD:-password}"

# create db if missing
if ! psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  echo "[entry] creating database ${DB_NAME}"
  createdb "${DB_NAME}"
  # base install once, then exit; if it fails, print logs and exit non-zero
  echo "[entry] installing base in ${DB_NAME}"
  if ! odoo -d "${DB_NAME}" -i base --without-demo=all --stop-after-init; then
    echo "[entry] base install failed — last 200 lines of log:"
    tail -n 200 /var/lib/odoo/.local/share/Odoo/log/* 2>/dev/null || true
    exit 1
  fi
else
  echo "[entry] database ${DB_NAME} already exists — skipping base install"
fi

echo "[entry] launching odoo server on 8069"
exec odoo -d "${DB_NAME}"
