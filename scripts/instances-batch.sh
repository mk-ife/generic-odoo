#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

COUNT="${1:-}"
PREFIX="${2:-demo}"
DOMAIN_BASE="${3:-}"     # leer = ohne Traefik, sonst z.B. 91-107-228-241.nip.io
PARALLEL="${4:-5}"       # wie viele parallel starten

if [[ -z "${COUNT}" ]]; then
  echo "Usage: scripts/instances-batch.sh <COUNT> [PREFIX] [DOMAIN_BASE] [PARALLEL]"; exit 1
fi

# Namen vorab erzeugen und merken
declare -a NAMES=()
for n in $(seq 1 "${COUNT}"); do
  NAME_RAW="${PREFIX}${n}"
  NAME="$(echo "$NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  NAMES+=("$NAME")
done

# GNU parallel nicht voraussetzen -> einfache Job-Queue
running=0
for NAME in "${NAMES[@]}"; do
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

# ---------- Geordnete, vollständige Summary ----------
echo
echo "===== Summary ====="
if [[ -n "${DOMAIN_BASE}" ]]; then
  # Traefik-Fall: feste :80, echte Host-URL + --resolve Hinweis
  for NAME in "${NAMES[@]}"; do
    HOST="${NAME}.${DOMAIN_BASE}"
    echo "Open:   http://${HOST}/web"
    echo "Test:   curl -sI --resolve '${HOST}:80:127.0.0.1' http://${HOST}/web/login | sed -n '1,5p'"
  done
  echo "Note:   Requests gehen via Traefik (:80) – daher '--resolve …:80:127.0.0.1'."
else
  # Ohne Traefik: deterministische Portberechnung wie in instance-up.sh
  BASE=8069
  for NAME in "${NAMES[@]}"; do
    OFFSET=$(( ( $(echo -n "${NAME}" | cksum | awk '{print $1}') % 200 ) ))
    PORT=$(( BASE + OFFSET ))
    echo "Open:   http://127.0.0.1:${PORT}/web"
    echo "Test:   curl -sI http://127.0.0.1:${PORT}/web/login | sed -n '1,5p'"
  done
fi
echo "===================="
