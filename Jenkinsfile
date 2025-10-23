pipeline {
  agent any
  options {
    skipDefaultCheckout(true)
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    string(name: 'COUNT',       defaultValue: '1',    description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX',      defaultValue: 'demo', description: 'Instanz-Prefix, z.B. "kunde-a-"')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'leer = ohne Traefik; sonst Traefik-Domain-Basis')
    string(name: 'PARALLEL',    defaultValue: '1',    description: 'Parallel gestartete Jobs')

    booleanParam(name: 'ENABLE_TRAEFIK', defaultValue: true,  description: 'Traefik/Reverse-Proxy verwenden (Host-Routing)')
    booleanParam(name: 'FORCE_HTTPS',    defaultValue: true,  description: 'HTTPS Router (Let’s Encrypt) aktivieren')
    string(name: 'LE_EMAIL', defaultValue: 'admin@example.com', description: 'E-Mail für Let’s Encrypt (ACME)')

    choice(name: 'AUTH_MODE', choices: ['none','userpass','sshkey'], description: 'Zugriffsdaten-Quelle (optional)')
    credentials(name: 'AUTH_CREDENTIALS_ID', defaultValue: '', description: 'Jenkins-Credentials (User/Pass ODER SSH-Key, optional)')
    booleanParam(name: 'INCLUDE_SECRETS_IN_DASHBOARD', defaultValue: true, description: 'Zugangsdaten im Dashboard mit anzeigen')
  }

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    ODOO_INIT_SRC = "${WORKSPACE}/scripts/odoo-init"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''#!/usr/bin/env bash
set -eux
mkdir -p "$DOCKER_CONFIG/cli-plugins"
if [ ! -x "$COMPOSE_CLI" ]; then
  curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$COMPOSE_CLI"
  chmod +x "$COMPOSE_CLI"
fi
docker compose version
test -s "${ODOO_INIT_SRC}/entry.sh" || { echo "FEHLT: ${ODOO_INIT_SRC}/entry.sh"; exit 1; }
chmod +x "${ODOO_INIT_SRC}/entry.sh"
'''
      }
    }

    stage('Sanity: compose render + Mount prüfen') {
      steps {
        sh '''#!/usr/bin/env bash
set -eux
docker compose config | tee .compose.rendered.yaml | sed -n '1,200p'
grep -q "target: /opt/odoo-init" .compose.rendered.yaml
grep -q "/scripts/odoo-init" .compose.rendered.yaml || echo "Hinweis: compose zeigt absoluten Pfad; ok solange /opt/odoo-init target stimmt."
'''
      }
    }

    stage('Deploy batch') {
      steps {
        withEnv([
          "COUNT=${params.COUNT}",
          "PREFIX=${params.PREFIX}",
          "DOMAIN_BASE=${params.DOMAIN_BASE}",
          "PARALLEL=${params.PARALLEL}",
          "ODOO_INIT_SRC=${env.ODOO_INIT_SRC}",
          "ENABLE_TRAEFIK=${params.ENABLE_TRAEFIK}",
          "FORCE_HTTPS=${params.FORCE_HTTPS}",
          "LE_EMAIL=${params.LE_EMAIL}"
        ]) {
          sh '''#!/usr/bin/env bash
set -eux
# Traefik-Schalter für Compose (ohne ${COMPOSE_PROJECT_NAME} in der Shell zu benutzen!)
if [ "${ENABLE_TRAEFIK}" = "true" ] && [ -n "${DOMAIN_BASE}" ]; then
  export TRAEFIK_ENABLE=true
else
  export TRAEFIK_ENABLE=false
fi

# HTTPS/TLS für Compose via Variablen steuern (Compose expandiert im YAML)
if [ "${FORCE_HTTPS}" = "true" ]; then
  export TRAEFIK_ENTRYPOINTS="websecure"
  export TRAEFIK_TLS="true"
  export TRAEFIK_TLS_RESOLVER="le"
else
  export TRAEFIK_ENTRYPOINTS="web"
  export TRAEFIK_TLS="false"
  export TRAEFIK_TLS_RESOLVER=""
fi

cd "${WORKSPACE}"
./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true
'''
        }
      }
    }

    stage('Diagnose (bei Unhealthy)') {
      steps {
        sh '''#!/usr/bin/env bash
set -eux
LIST="$(docker ps -a --format '{{.Names}}' | grep -E '^'${PREFIX}'[0-9]+-odoo-1$' || true)"
[ -z "$LIST" ] && { echo "Keine Odoo-Container gefunden – nichts zu diagnostizieren."; exit 0; }
EXIT=0
for C in $LIST; do
  echo "==> Diagnose für Container: $C"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E "^$C\\b" || true
  echo "--- docker inspect (Mounts) ---"
  docker inspect "$C" --format '{{range .Mounts}}{{println .Destination " <- " .Source}}{{end}}' || true
  echo "--- Command ---"
  docker inspect "$C" --format 'Cmd: {{.Config.Cmd}}' || true
  echo "--- Dateien in /opt/odoo-init ---"
  docker exec "$C" sh -lc 'ls -l /opt/odoo-init || true' || true
  STATE="$(docker inspect "$C" --format '{{.State.Health.Status}}' 2>/dev/null || echo 'unknown')"
  echo "Health: $STATE"
  [ "$STATE" = "healthy" ] || EXIT=1
done
[ $EXIT -eq 0 ] || { echo "Mindestens eine Odoo-Instanz ist unhealthy."; exit 1; }
'''
      }
    }

    stage('Smoke') {
      when { expression { return params.COUNT?.trim() != '' } }
      steps {
        sh '''#!/usr/bin/env bash
set -eux
for i in $(seq 1 ${COUNT}); do
  NAME="${PREFIX}${i}"
  if [ -n "${DOMAIN_BASE}" ]; then
    HOST="${NAME}.${DOMAIN_BASE}"
    if [ "${FORCE_HTTPS}" = "true" ]; then
      echo "Smoke: https://${HOST}/web/login"
      curl -sI -k --resolve "${HOST}:443:127.0.0.1" "https://${HOST}/web/login" | sed -n '1,10p'
    else
      echo "Smoke: http://${HOST}/web/login"
      curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,10p'
    fi
  else
    PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
    echo "Smoke: http://127.0.0.1:${PORT}/web/login"
    curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,10p'
  fi
done
'''
      }
    }
  }
}
