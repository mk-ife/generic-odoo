#!/usr/bin/env bash
set -euo pipefail

COUNT="${1:-1}"                 # wie viele
PREFIX="${2:-demo}"             # prefix (z.B. 'demo')
DOMAIN_BASE="${3:-}"            # z.B. '91-107-228-241.nip.io' (leer = ohne Traefik/Host-Routing)
PARALLEL="${4:-1}"              # parallelität (derzeit nicht genutzt)
ODOO_INIT_SRC="${ODOO_INIT_SRC:-./scripts/odoo-init}"

echo "==> instances-batch: COUNT=${COUNT} PREFIX=${PREFIX} DOMAIN_BASE='${DOMAIN_BASE}' PARALLEL=${PARALLEL}"

# Sanity: init-script vorhanden
test -s "${ODOO_INIT_SRC}/entry.sh" || { echo "ERROR: ${ODOO_INIT_SRC}/entry.sh fehlt!"; exit 1; }

for i in $(seq 1 "${COUNT}"); do
  NAME="${PREFIX}${i}"
  if [ -n "${DOMAIN_BASE}" ]; then
    HOST="${NAME}.${DOMAIN_BASE}"
  else
    HOST=""
  fi

  echo "==> Starting ${NAME} ..."
  # Compose-Umgebung. WICHTIG: COMPOSE_PROJECT_NAME & VIRTUAL_HOST für Traefik-Labels
  export COMPOSE_PROJECT_NAME="${NAME}"
  export VIRTUAL_HOST="${HOST}"

  # Falls Traefik verwendet werden soll, stelle sicher, dass das 'proxy'-Netz existiert
  if [ -n "${HOST}" ]; then
    docker network create proxy 2>/dev/null || true
  fi

  # Start
  ODOO_INIT_SRC="${ODOO_INIT_SRC}" \
  docker compose up -d

  # Kurze Diagnose (hostseitig): zeigt das lokale Init-Verzeichnis
  if [ -n "${HOST}" ]; then
    echo "--- host init dir ---"
    ls -l "${ODOO_INIT_SRC}" || true
  fi

  # Readiness-Check: warte kurz bis Healthchecks ok / oder 90s Timeout
  echo "Waiting for Odoo to be ready..."
  deadline=$(( $(date +%s) + 90 ))
  ok=0
  while [ $(date +%s) -lt $deadline ]; do
    state="$(docker inspect "${NAME}-odoo-1" --format '{{.State.Health.Status}}' 2>/dev/null || echo 'unknown')"
    [ "${state}" = "healthy" ] && { ok=1; break; }
    sleep 3
  done

  if [ $ok -ne 1 ]; then
    echo "WARN: Odoo readiness check timed out. Diagnostics:"
    docker compose -p "${NAME}" ps
    docker compose -p "${NAME}" logs --tail=200 odoo || true
  fi

  if [ -n "${HOST}" ]; then
    echo "Test:   curl -sI --resolve '${HOST}:80:127.0.0.1' http://${HOST}/web/login | sed -n '1,5p'"
    echo "Open:   http://${HOST}/web"
    echo "Note:   Request via Traefik (:80) – deshalb '--resolve …:80:127.0.0.1'."
  fi
done

echo "==> Batch complete."
