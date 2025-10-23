#!/usr/bin/env bash
set -euo pipefail

COUNT="${1:-1}"                 # wie viele
PREFIX="${2:-demo}"             # prefix (z.B. 'demo')
DOMAIN_BASE="${3:-}"            # z.B. '91-107-228-241.nip.io' (leer = ohne Traefik/Host-Routing)
PARALLEL="${4:-1}"              # parallelität
ODOO_INIT_SRC="${ODOO_INIT_SRC:-./scripts/odoo-init}"

echo "==> instances-batch: COUNT=${COUNT} PREFIX=${PREFIX} DOMAIN_BASE='${DOMAIN_BASE}' PARALLEL=${PARALLEL}"
echo "==> ODOO_INIT_SRC host path: ${ODOO_INIT_SRC}"
test -d "${ODOO_INIT_SRC}" || { echo "ERROR: Verzeichnis ${ODOO_INIT_SRC} existiert nicht"; exit 2; }
ls -la "${ODOO_INIT_SRC}"
test -s "${ODOO_INIT_SRC}/entry.sh" || { echo "ERROR: ${ODOO_INIT_SRC}/entry.sh fehlt oder ist leer"; exit 3; }
chmod +x "${ODOO_INIT_SRC}/entry.sh" || true

for i in $(seq 1 "${COUNT}"); do
  NAME="${PREFIX}${i}"
  export COMPOSE_PROJECT_NAME="${NAME}"
  if [ -n "${DOMAIN_BASE}" ]; then
    export VIRTUAL_HOST="${NAME}.${DOMAIN_BASE}"
    docker network create proxy 2>/dev/null || true
  else
    export VIRTUAL_HOST=""
  fi

  # --- Init-Volume anlegen und aus Repo befüllen ---
  VOL="${COMPOSE_PROJECT_NAME}_odoo_init"
  echo "==> Prepare init volume: ${VOL}"
  docker volume create "${VOL}" >/dev/null

  # DEBUG + robustes Kopieren (im Container)
  docker run --rm \
    -v "${VOL}:/dst" \
    -v "${ODOO_INIT_SRC}:/src:ro" \
    alpine:3 sh -lc '
      set -e
      echo "--- /src Inhalt ---"
      ls -la /src || true
      test -s /src/entry.sh || { echo "FATAL: /src/entry.sh fehlt im Container-Mount"; exit 7; }
      rm -rf /dst/* || true
      # robust per tar-Stream kopieren (erhält Rechte besser als cp -r)
      tar -C /src -cf - . | tar -C /dst -xf -
      chmod 755 /dst/entry.sh
      echo "--- /dst Inhalt (nach Copy) ---"
      ls -la /dst
    '

  # --- Start mit beiden Compose-Dateien (Basis + Volume-Name Overlay) ---
  echo "==> Starting ${NAME} ..."
  docker compose -f docker-compose.yml -f docker-compose.init.yml up -d

  # Readiness-Check (90s Timeout)
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
    docker compose -p "${NAME}" ps || true
    docker compose -p "${NAME}" logs --tail=200 odoo || true
  fi

  if [ -n "${VIRTUAL_HOST}" ]; then
    echo "Test:   curl -sI --resolve '${VIRTUAL_HOST}:80:127.0.0.1'  http://${VIRTUAL_HOST}/web/login | sed -n '1,6p'"
    echo "Test:   curl -k -sI --resolve '${VIRTUAL_HOST}:443:127.0.0.1' https://${VIRTUAL_HOST}/web/login | sed -n '1,6p'"
    echo "Open:   http://${VIRTUAL_HOST}/web"
  fi
done

echo "==> Batch complete."
