#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Compose-Erkennung laden (nur falls wir -p logs etc. brauchen)
source scripts/_dc.sh || true

COUNT="${1:-}"
PREFIX="${2:-demo}"
DOMAIN_BASE="${3:-}"     # leer = ohne Traefik, sonst z.B. 91-107-228-241.nip.io
PARALLEL="${4:-5}"       # wie viele parallel starten

if [[ -z "${COUNT}" ]]; then
  echo "Usage: scripts/instances-batch.sh <COUNT> [PREFIX] [DOMAIN_BASE] [PARALLEL]"
  exit 1
fi

# Falls PARALLEL leer oder <1 => 1 (kein echtes Parallel)
if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -lt 1 ]]; then
  PARALLEL=1
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
