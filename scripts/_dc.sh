#!/usr/bin/env bash
set -euo pipefail

# 1) docker compose (v2) lokal?
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
  export DC
  return 0 2>/dev/null || exit 0
fi

# 2) docker-compose (v1) lokal?
if command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
  export DC
  return 0 2>/dev/null || exit 0
fi

# 3) Fallback: Compose-in-Docker (Compose v2 aus GHCR)
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
if [[ ! -S "${DOCKER_SOCKET}" ]]; then
  echo "ERROR: Docker socket not found at ${DOCKER_SOCKET}. Cannot run compose." >&2
  exit 1
fi

COMPOSE_IMAGE="${COMPOSE_IMAGE:-ghcr.io/docker/compose:latest}"

# Versuche Image vorab zu ziehen (nur Warnung bei Fail, run versucht es nochmal)
if command -v docker >/dev/null 2>&1; then
  docker pull "${COMPOSE_IMAGE}" >/dev/null 2>&1 || true
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
  "${COMPOSE_IMAGE}")

export DC
