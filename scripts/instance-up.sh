#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

RAW_NAME="${1:-}"     # z.B. demo1
PORT="${2:-}"         # optional (nur ohne Traefik)
HOST="${3:-}"         # optional (Traefik Host, z.B. demo1.example.tld)

if [[ -z "${RAW_NAME}" ]]; then
  echo "Usage: scripts/instance-up.sh <NAME> [PORT] [VIRTUAL_HOST]"; exit 1
fi

# Projektname säubern
NAME="$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
NAME="$(echo "$NAME" | sed 's/^[^a-z0-9]//')"
if [[ -z "${NAME}" ]]; then
  echo "ERROR: resulting name is empty after sanitizing."; exit 1
fi

export COMPOSE_PROJECT_NAME="${NAME}"
export POSTGRES_USER="${POSTGRES_USER:-odoo}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
export POSTGRES_DB="${POSTGRES_DB:-${COMPOSE_PROJECT_NAME}_db}"

# Traefik on/off
if [[ -n "${HOST:-}" ]]; then
  export TRAEFIK_ENABLE="true"
  export VIRTUAL_HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"
else
  export TRAEFIK_ENABLE="${TRAEFIK_ENABLE:-false}"
fi

# Port nur ohne Traefik
if [[ "${TRAEFIK_ENABLE}" != "true" ]]; then
  if [[ -z "${PORT:-}" ]]; then
    BASE=8069
    OFFSET=$(( ( $(echo -n "${COMPOSE_PROJECT_NAME}" | cksum | awk '{print $1}') % 200 ) ))
    PORT=$(( BASE + OFFSET ))
  fi
  export ODOO_PORT="${PORT}"
fi

# ---------- Init-Skript (hostseitig) vorbereiten ----------
INIT_SRC_DIR="./tmp/${COMPOSE_PROJECT_NAME}-init-src"
mkdir -p "${INIT_SRC_DIR}"
cat > "${INIT_SRC_DIR}/entry.sh" <<'ENTRY'
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
ENTRY
chmod +x "${INIT_SRC_DIR}/entry.sh"

# ---------- Named Volume befüllen (ohne Host-Pfadabhängigkeit) ----------
VOL_NAME="${COMPOSE_PROJECT_NAME}_odoo_init"
docker volume create "${VOL_NAME}" >/dev/null

# temp container starten mit gemountetem Volume
TMP_C="initcp-${COMPOSE_PROJECT_NAME}-$$"
docker run -d --name "${TMP_C}" -v "${VOL_NAME}:/dst" alpine:3 sh -lc "sleep 600" >/dev/null

# Dateien per docker cp in den Container kopieren (funktioniert auch aus Jenkins-Container)
docker cp "${INIT_SRC_DIR}/." "${TMP_C}:/dst/"

# Rechte setzen im Container
docker exec "${TMP_C}" sh -lc "chmod 755 /dst/entry.sh && ls -l /dst" || true

# temp container beenden/aufräumen
docker rm -f "${TMP_C}" >/dev/null 2>&1 || true

echo "==> Starting ${COMPOSE_PROJECT_NAME} ..."

# ---------- Start: Compose mit init-override (Volume) ----------
set +e
docker compose -p "${COMPOSE_PROJECT_NAME}" \
  -f docker-compose.yml \
  -f docker-compose.init.yml \
  up -d --wait
UP_RC=$?
set -e

# Readiness check (max 90s), unabhängig vom RC
echo "Waiting for Odoo to be ready..."
READY=0
for i in $(seq 1 90); do
  if [[ "${TRAEFIK_ENABLE}" == "true" ]]; then
    if curl -fsS -m 2 -H "Host: ${VIRTUAL_HOST}" http://127.0.0.1/web/login >/dev/null 2>&1; then READY=1; break; fi
  else
    if curl -fsS -m 2 "http://127.0.0.1:${ODOO_PORT}/web/login" >/dev/null 2>&1; then READY=1; break; fi
  fi
  sleep 1
done

if [[ "${READY}" != "1" ]]; then
  echo "WARN: Odoo readiness check timed out. Diagnostics:"
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

# nie hart failen – Diagnose macht die Pipeline
exit 0
