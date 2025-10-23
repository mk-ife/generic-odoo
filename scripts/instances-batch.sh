#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

COUNT="${1:-}"
PREFIX="${2:-demo}"
DOMAIN_BASE="${3:-}"
PARALLEL="${4:-5}"

if [[ -z "${COUNT}" ]]; then
  echo "Usage: scripts/instances-batch.sh <COUNT> [PREFIX] [DOMAIN_BASE] [PARALLEL]"; exit 1
fi

running=0
for n in $(seq 1 "${COUNT}"); do
  NAME_RAW="${PREFIX}${n}"
  NAME="$(echo "$NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  if [[ -n "${DOMAIN_BASE}" ]]; then
    HOST="${NAME}.${DOMAIN_BASE}"
    ./scripts/instance-up.sh "${NAME}" "" "${HOST}" &
  else
    ./scripts/instance-up.sh "${NAME}" &
  fi
  running=$((running+1))
  if [[ "${running}" -ge "${PARALLEL}" ]]; then
    wait -n
    running=$((running-1))
  fi
done
wait
echo "==> Batch complete."
