#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Compose-Erkennung laden
source scripts/_dc.sh

RAW_NAME="${1:-}"     # z.B. DemoA
PORT="${2:-}"         # optional (nur ohne Traefik)
HOST="${3:-}"         # optional (Traefik Host, z.B. demo1.91-107-228-241.nip.io)

if [[ -z "${RAW_NAME}" ]]; then
  echo "Usage: scripts/instance-up.sh <NAME> [PORT] [VIRTUAL_HOST]"; exit 1
fi

# Compose-Projektname: nur lowercase a-z0-9_- und muss mit Buchstabe/Zahl beginnen
NAME="$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
NAME="$(echo "$NAME" | sed 's/^[^a-z0-9]//')"   # führende ungültige Zeichen entfernen
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
  # Falls kein Port übergeben: automatisch berechnen (Basis 8069 + Hash)
  if [[ -z "${PORT:-}" ]]; then
    BASE=8069
    OFFSET=$(( ( $(echo -n "${COMPOSE_PROJECT_NAME}" | cksum | awk '{print $1}') % 200 ) ))
    PORT=$(( BASE + OFFSET ))
  fi
  export ODOO_PORT="${PORT}"
fi

# Start
"${DC[@]}" -p "${COMPOSE_PROJECT_NAME}" up -d --wait

# Readiness check (max 90s)
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
  echo "WARN: Odoo readiness check timed out. Check logs below:"
  "${DC[@]}" -p "${COMPOSE_PROJECT_NAME}" logs --tail=200 || true
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
