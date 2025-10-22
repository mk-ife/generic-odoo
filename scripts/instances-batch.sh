#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

COUNT="${1:-}"
PREFIX="${2:-demo}"
DOMAIN_BASE="${3:-}"     # leer = ohne Traefik, sonst z.B. 91-107-228-241.nip.io
PARALLEL="${4:-5}"

if [[ -z "${COUNT}" ]]; then
  echo "Usage: scripts/instances-batch.sh <COUNT> [PREFIX] [DOMAIN_BASE] [PARALLEL]"; exit 1
fi

INIT_SRC="$(pwd)/scripts/odoo-init"
test -x "${INIT_SRC}/entry.sh" || { echo "ERROR: ${INIT_SRC}/entry.sh fehlt/ist nicht ausführbar"; exit 1; }

run_one() {
  local NAME_RAW="$1"
  local NAME="$(echo "$NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"

  export COMPOSE_PROJECT_NAME="${NAME}"
  export POSTGRES_USER="${POSTGRES_USER:-odoo}"
  export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
  export POSTGRES_DB="${POSTGRES_DB:-${COMPOSE_PROJECT_NAME}_db}"
  # >>> hier legen wir den Bind-Mount fest
  export ODOO_INIT_SRC="${INIT_SRC}"

  if [[ -n "${DOMAIN_BASE}" ]]; then
    export TRAEFIK_ENABLE="true"
    export VIRTUAL_HOST="${NAME}.${DOMAIN_BASE}"
  else
    export TRAEFIK_ENABLE="${TRAEFIK_ENABLE:-false}"
    unset VIRTUAL_HOST || true
  fi

  echo "==> Starting ${NAME} ..."
  docker compose -p "${NAME}" up -d --wait

  echo "Waiting for Odoo to be ready..."
  for i in $(seq 1 90); do
    if [[ "${TRAEFIK_ENABLE}" == "true" ]]; then
      if curl -fsS -m 2 --resolve "${VIRTUAL_HOST}:80:127.0.0.1" "http://${VIRTUAL_HOST}/web/login" >/dev/null 2>&1; then
        READY=1; break
      fi
    else
      PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
      if [[ -n "${PORT:-}" ]] && curl -fsS -m 2 "http://127.0.0.1:${PORT}/web/login" >/dev/null 2>&1; then
        READY=1; break
      fi
    fi
    sleep 1
  done

  if [[ "${READY:-0}" != "1" ]]; then
    echo "WARN: Odoo readiness check timed out. Diagnostics:"
    docker compose -p "${NAME}" ps
    echo "---- odoo logs (last 200) ----"
    docker compose -p "${NAME}" logs --tail=200 odoo || true
    echo "---- db logs (last 100) ----"
    docker compose -p "${NAME}" logs --tail=100 db || true
  else
    echo "==> Up: ${NAME} is ready."
    if [[ "${TRAEFIK_ENABLE}" == "true" ]]; then
      echo "Test:   curl -sI --resolve '${VIRTUAL_HOST}:80:127.0.0.1' http://${VIRTUAL_HOST}/web/login | sed -n '1,5p'"
      echo "Open:   http://${VIRTUAL_HOST}/web"
      echo "Note:   Request via Traefik (:80) – deshalb '--resolve …:80:127.0.0.1'."
    else
      PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
      echo "Port:   ${PORT}"
      echo "Test:   curl -sI http://127.0.0.1:${PORT}/web/login | sed -n '1,5p'"
      echo "Open:   http://127.0.0.1:${PORT}/web"
    fi
  fi
}

running=0
for n in $(seq 1 "${COUNT}"); do
  NAME_RAW="${PREFIX}${n}"
  run_one "${NAME_RAW}" &
  running=$((running+1))
  if [[ "${running}" -ge "${PARALLEL}" ]]; then
    wait -n
    running=$((running-1))
  fi
done
wait
echo "==> Batch complete."
