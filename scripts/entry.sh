#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DESIRED_DB="${DESIRED_DB:-${POSTGRES_DB:-${COMPOSE_PROJECT_NAME:-odoo}_db}}"

ODOO_DB_ARGS=(--db_host "${DB_HOST}" --db_port "${DB_PORT}" --db_user "${DB_USER}" --db_password "${DB_PASSWORD}")

echo "[odoo-init] DB=${DESIRED_DB} on ${DB_HOST}:${DB_PORT} (user=${DB_USER})"

# Warten bis Postgres TCP offen ist
for i in {1..180}; do
  if bash -lc "exec 3<>/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
    echo "[odoo-init] postgres reachable"
    break
  fi
  sleep 1
done

# Idempotent initialisieren
tries=0
until [ $tries -ge 5 ]; do
  set +e
  echo "[odoo-init] init attempt $((tries+1))/5: odoo -d ${DESIRED_DB} -i base --stop-after-init ${ODOO_DB_ARGS[*]}"
  odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}" -i base --stop-after-init
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    echo "[odoo-init] base installed (or already up-to-date)"
    break
  fi
  tries=$((tries+1))
  sleep 5
done

echo "[odoo-init] starting odoo httpd..."
exec odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}"
