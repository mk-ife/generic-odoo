#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DB_NAME="${DESIRED_DB:-${COMPOSE_PROJECT_NAME}_db}"

echo "[entry] Odoo init"
echo "[entry] DB_HOST=${DB_HOST} DB_PORT=${DB_PORT} DB_USER=${DB_USER} DB_NAME=${DB_NAME}"

# Hinweis: postgres ist via depends_on:healthy bereits ready
# POSTGRES_DB sorgt dafür, dass die DB existiert.

echo "[entry] installing base (idempotent)"
# Wenn bereits installiert, ist der Durchlauf kurz.
odoo \
  --db_host="${DB_HOST}" --db_port="${DB_PORT}" \
  --db_user="${DB_USER}" --db_password="${DB_PASSWORD}" \
  -d "${DB_NAME}" -i base --without-demo=all --stop-after-init || {
    echo "[entry] base install returned non-zero; fahre trotzdem mit Serverstart fort, um Logs zu erhalten"
  }

echo "[entry] starting odoo server on :8069"
exec odoo \
  --db_host="${DB_HOST}" --db_port="${DB_PORT}" \
  --db_user="${DB_USER}" --db_password="${DB_PASSWORD}" \
  -d "${DB_NAME}"
