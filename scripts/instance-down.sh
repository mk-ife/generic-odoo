#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="${1:-}"
if [[ -z "$NAME" ]]; then echo "Usage: scripts/instance-down.sh <NAME>"; exit 1; fi
docker compose -p "$NAME" down -v
echo "==> Down & Purged: $NAME"
