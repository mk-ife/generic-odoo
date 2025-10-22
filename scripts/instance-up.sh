#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

RAW_NAME="${1:-}"     # z.B. DemoA
PORT="${2:-}"         # optional (nur ohne Traefik)
HOST="${3:-}"         # optional (Traefik Host, z.B. demo1.example.tld)

if [[ -z "${RAW_NAME}" ]]; then
  echo "Usage: scripts/instance-up.sh <NAME> [PORT] [VIRTUAL_HOST]"; exit 1
fi

# Compose-Projektname: nur lowercase a-z0-9_- und muss mit Buchstabe/Zahl beginnen
NAME="$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
NAME="$(echo "$NAME" | sed 's/^[a-z0-9].*//;t;:x; s/^[^a-z0-9]//; tx')"
# Fallback falls erste Zeile leer (extrem selten)
if [[ -z "${NAME}" ]]; then
  NAME="$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"
fi
if [[ -z "${NAME}" ]]; then
  echo "ERROR: resulting name is empty after sanitizing."; exit 1
fi

export COMPOSE_PROJECT_NAME="${NAME}"
export POSTGRES_USER="${POSTGRES_USER:-odoo}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
export POSTGRES_DB="${POSTGRES_DB:-${COMPOSE_PROJECT_NAME}_db}"

# Traefik automatisch aktivieren, wenn HOST angegeben wird
if [[ -n "${HOST:-}" ]]; then
  export TRAEFIK_ENABLE="true"
  export VIRTUAL_HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"
else
  export TRAEFIK_ENABLE="${TRAEFIK_ENABLE:-false}"
fi

# Port nur ohne Traefik verwenden
if [[ "${TRAEFIK_ENABLE}" != "true" ]]; then
  if [[ -z "${PORT:-}" ]]; then
    BASE=8069
    OFFSET=$(( ( $(echo -n "${COMPOSE_PROJECT_NAME}" | cksum | awk '{print $1}') % 200 ) ))
    PORT=$(( BASE + OFFSET ))
  fi
  export ODOO_PORT="${PORT}"
fi

# --- Inline-Init vorbereiten: pro Instanz einen Ordner mit entry.sh bauen ---
INIT_DIR="./tmp/${COMPOSE_PROJECT_NAME}-init"
mkdir -p "${INIT_DIR}"
cat > "${INIT_DIR}/entry.sh" <<'ENTRY'
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

# Idempotente Grundinstallation
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
ENTRY
chmod +x "${INIT_DIR}/entry.sh"

echo "==> Starting ${COMPOSE_PROJECT_NAME} ..."

# Start mit Init-Override (bind-mount des INIT_DIR nach /opt/odoo-init)
set +e
docker compose -p "${COMPOSE_PROJECT_NAME}" \
  -f docker-compose.yml \
  -f docker-compose.init.yml \
  up -d --wait
UP_RC=$?
set -e

# Schnelle Sichtprüfung, ob entry.sh drin ist
echo "--- host init dir ---"
ls -l "${INIT_DIR}" || true

# Readiness check (max 90s), auch wenn --wait nonzero war
echo "Waiting for Odoo to be ready..."
READY=0
for i in $(seq 1 90); do
  if [[ "${TRAEFIK_ENABLE}" == "true" ]]; then
    if curl -fsS -m 2 -H "Host: ${VIRTUAL_HOST}" http://127.0.0.1/web/login >/dev/null 2>&1; then
      READY=1; break
    fi
  else
    if curl -fsS -m 2 "http://127.0.0.1:${ODOO_PORT}/web/login" >/dev/null 2>&1; then
      READY=1; break
    fi
  fi
  sleep 1
done

if [[ "${READY}" != "1" ]]; then
  echo "WARN: Odoo readiness check timed out. Logs:"
  docker compose -p "${COMPOSE_PROJECT_NAME}" ps
  docker compose -p "${COMPOSE_PROJECT_NAME}" logs --tail=200 || true
else
  echo "==> Up: ${COMPOSE_PROJECT_NAME} is ready."
fi

# Hints
if [[ "${TRAEFIK_ENABLE}" == "true" ]]; then
  echo "Test:   curl -sI --resolve '${VIRTUAL_HOST}:80:127.0.0.1' http://${VIRTUAL_HOST}/web/login | sed -n '1,5p'"
  echo "Open:   http://${VIRTUAL_HOST}/web"
  echo "Note:   Request via Traefik (:80) – deshalb '--resolve …:80:127.0.0.1'."
else
  echo "Port:   ${ODOO_PORT}"
  echo "Test:   curl -sI http://127.0.0.1:${ODOO_PORT}/web/login | sed -n '1,5p'"
  echo "Open:   http://127.0.0.1:${ODOO_PORT}/web"
fi

# Niemals mit Fehler rausfallen – Diagnose übernimmt Pipeline
exit 0
