#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

COUNT="${1:-}"
PREFIX="${2:-demo}"
DOMAIN_BASE="${3:-}"   # leer = ohne Traefik, sonst z.B. 91-107-228-241.nip.io
PARALLEL="${4:-5}"     # wie viele parallel starten

if [[ -z "${COUNT}" ]]; then
  echo "Usage: scripts/instances-batch.sh <COUNT> [PREFIX] [DOMAIN_BASE] [PARALLEL]" ; exit 1
fi

# Quelle für den Bind-Mount (hier direkt aus dem Repo)
INIT_SRC="$(pwd)/scripts/odoo-init"
ENTRY="${INIT_SRC}/entry.sh"
if [[ ! -x "${ENTRY}" ]]; then
  echo "ERROR: ${ENTRY} fehlt oder ist nicht ausführbar!" >&2
  echo "Fix z.B.:  chmod +x scripts/odoo-init/entry.sh" >&2
  exit 1
fi

run_one() {
  local NAME_RAW="$1"
  local NAME="$(echo "$NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  local OVR
  OVR="$(mktemp -t "${NAME}.ovr.XXXXXX.yml")"

  # optionaler Hostname für Traefik
  if [[ -n "${DOMAIN_BASE}" ]]; then
    export TRAEFIK_ENABLE="true"
    export VIRTUAL_HOST="${NAME}.${DOMAIN_BASE}"
  else
    export TRAEFIK_ENABLE="${TRAEFIK_ENABLE:-false}"
    unset VIRTUAL_HOST || true
  fi

  export COMPOSE_PROJECT_NAME="${NAME}"
  export POSTGRES_USER="${POSTGRES_USER:-odoo}"
  export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
  export POSTGRES_DB="${POSTGRES_DB:-${COMPOSE_PROJECT_NAME}_db}"

  # Compose-Override: erzwingt BIND-MOUNT auf /opt/odoo-init
  cat > "${OVR}" <<YAML
services:
  odoo:
    volumes:
      - ${INIT_SRC}:/opt/odoo-init:ro
YAML

  echo "==> Starting ${NAME} ..."
  # Sanity: prüfen, dass das Rendern wirklich einen bind mount ergibt
  if ! docker compose -p "${NAME}" -f docker-compose.yml -f "${OVR}" config \
     | awk 'BEGIN{ok=0} /target: \/opt\/odoo-init/ {seen=1} seen && /type: bind/ {ok=1} END{exit ok?0:1}'; then
     echo "FATAL: Override setzt /opt/odoo-init nicht als bind mount. Abbruch." >&2
     echo "--- Rendered ---" >&2
     docker compose -p "${NAME}" -f docker-compose.yml -f "${OVR}" config >&2 || true
     exit 1
  fi

  # Start
  docker compose -p "${NAME}" -f docker-compose.yml -f "${OVR}" up -d --wait

  # Readiness + Ausgabe wie gewohnt
  echo "Waiting for Odoo to be ready..."
  for i in $(seq 1 90); do
    if [[ "${TRAEFIK_ENABLE:-false}" == "true" ]]; then
      if curl -fsS -m 2 --resolve "${VIRTUAL_HOST}:80:127.0.0.1" "http://${VIRTUAL_HOST}/web/login" >/dev/null 2>&1; then
        READY=1; break
      fi
    else
      # ohne Traefik: Port ermitteln
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
    if [[ "${TRAEFIK_ENABLE:-false}" == "true" ]]; then
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

  echo "==> NOTE: /opt/odoo-init ist Bind-Mount von ${INIT_SRC} (aus dem Repo)."
  echo "          Kein zusätzliches Volume notwendig."
}

# einfache „Job-Queue“ ohne GNU parallel
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
