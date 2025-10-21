#!/usr/bin/env bash
set -euo pipefail

# Liefert den Compose-Befehl in der Array-Variable DC zurück (per source nutzbar).
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  echo "ERROR: Docker Compose (v2 'docker compose' oder v1 'docker-compose') nicht gefunden." >&2
  exit 1
fi
export DC
