#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DESIRED_DB:-${COMPOSE_PROJECT_NAME}_db}"

echo "[entry] Odoo init"
echo "[entry] DB_HOST=${DB_HOST:-db} DB_PORT=${DB_PORT:-5432} DB_USER=${DB_USER:-odoo} DB_NAME=${DB_NAME}"

# Dank depends_on:service_healthy ist Postgres bereits bereit.
# POSTGRES_DB erstellt die Ziel-DB automatisch beim Start des postgres-Containers.

echo "[entry] installing base (idempotent)"
# Falls base schon installiert ist, ist der Lauf kurz und harmlos
odoo -d "${DB_NAME}" -i base --without-demo=all --stop-after-init || {
  echo "[entry] base install returned non-zero; continuing to run server to surface logs"
}

echo "[entry] starting odoo server on :8069"
exec odoo -d "${DB_NAME}"
