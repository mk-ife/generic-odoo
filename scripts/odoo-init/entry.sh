#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DESIRED_DB="${DESIRED_DB:-${POSTGRES_DB:-${COMPOSE_PROJECT_NAME:-odoo}_db}}"

# Odoo Admin (für DB-Manager/Web-Login)
ODOO_ADMIN_USER="${ODOO_ADMIN_USER:-admin}"
ODOO_ADMIN_PASS="${ODOO_ADMIN_PASS:-admin}"

ODOO_DB_ARGS=(--db_host "$DB_HOST" --db_port "$DB_PORT" --db_user "$DB_USER" --db_password "$DB_PASSWORD")

echo "[odoo-init] DB=${DESIRED_DB} host=${DB_HOST}:${DB_PORT} db_user=${DB_USER}"
echo "[odoo-init] admin_user=${ODOO_ADMIN_USER}"

# Warten bis Postgres TCP offen ist
for i in {1..180}; do
  if bash -lc "exec 3<>/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
    echo "[odoo-init] postgres reachable"
    break
  fi
  sleep 1
done

# Basis installieren / updaten
tries=0
until [ $tries -ge 5 ]; do
  set +e
  echo "[odoo-init] init attempt $((tries+1))/5"
  odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}" -i base --stop-after-init --admin_passwd "${ODOO_ADMIN_PASS}"
  rc=$?
  set -e
  [ $rc -eq 0 ] && break
  tries=$((tries+1))
  sleep 5
done

echo "[odoo-init] starting odoo httpd..."
exec odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}" --admin_passwd "${ODOO_ADMIN_PASS}"
