#!/usr/bin/env bash
set -euo pipefail

# 1) docker compose (v2) vorhanden?
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
  export DC
  return 0
fi

# 2) docker-compose (v1) vorhanden?
if command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
  export DC
  return 0
fi

# 3) Fallback: Compose-in-Docker (offizielles Image)
#    Voraussetzung: Jenkins-User hat Zugriff auf /var/run/docker.sock
#    Wir mounten:
#      - Docker Socket
#      - aktuelles Arbeitsverzeichnis (PWD)
#    und übergeben die wichtigen ENV-Variablen an den Container.
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
if [[ ! -S "${DOCKER_SOCKET}" ]]; then
  echo "ERROR: Docker socket not found at ${DOCKER_SOCKET}. Cannot run compose." >&2
  exit 1
fi

DC=(docker run --rm
  -v "${DOCKER_SOCKET}:/var/run/docker.sock"
  -v "${PWD}:${PWD}"
  -w "${PWD}"
  -e COMPOSE_PROJECT_NAME
  -e POSTGRES_USER
  -e POSTGRES_PASSWORD
  -e POSTGRES_DB
  -e TRAEFIK_ENABLE
  -e VIRTUAL_HOST
  -e ODOO_PORT
  docker/compose:2.27.1)

export DC
