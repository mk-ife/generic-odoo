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

    // Neu: HTTPS/Traefik/LE/Authentifizierung
    booleanParam(name: 'ENABLE_TRAEFIK', defaultValue: true,  description: 'Traefik/Reverse-Proxy (Host-Routing) verwenden')
    booleanParam(name: 'FORCE_HTTPS',    defaultValue: true,  description: 'HTTPS Router (Let’s Encrypt) aktivieren')
    string(name: 'LE_EMAIL', defaultValue: 'admin@example.com', description: 'E-Mail für Let’s Encrypt (ACME)')

    choice(name: 'AUTH_MODE', choices: ['none','basic','ssh'], description: 'Zugriffsdaten-Quelle')
    string(name: 'AUTH_CREDENTIALS_ID', defaultValue: '', description: 'Jenkins-Credentials ID (Username/Password ODER SSH-Key)')
    booleanParam(name: 'INCLUDE_SECRETS_IN_DASHBOARD', defaultValue: true, description: 'Zugangsdaten im Dashboard mitspeichern (nicht im Log)')
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
        sh '''
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
        sh '''
          set -eux
          docker compose config | tee .compose.rendered.yaml | sed -n '1,200p'
          grep -q "target: /opt/odoo-init" .compose.rendered.yaml
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        script {
          // Traefik/HTTPS Umschalter -> nur ENV setzen, Deploy bleibt wie gehabt
          def envList = [
            "COUNT=${params.COUNT}",
            "PREFIX=${params.PREFIX}",
            "DOMAIN_BASE=${params.DOMAIN_BASE}",
            "PARALLEL=${params.PARALLEL}",
            "ODOO_INIT_SRC=${env.ODOO_INIT_SRC}",
            "TRAEFIK_ENABLE=${params.ENABLE_TRAEFIK ? 'true' : 'false'}",
            "TRAEFIK_TLS=${params.FORCE_HTTPS ? 'true' : 'false'}",
            "TRAEFIK_ENTRYPOINTS=${params.FORCE_HTTPS ? 'websecure' : 'web'}",
            "LE_RESOLVER=le",
            "LE_EMAIL=${params.LE_EMAIL}",
            "VIRTUAL_HOST=" // wird in scripts/inst... je Instanz gesetzt
          ]
          withEnv(envList) {
            sh '''
              set -eux
              ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true
            '''
          }
        }
      }
    }

    stage('Diagnose (bei Unhealthy)') {
      steps {
        sh '''
          set -eux
          LIST="$(docker ps -a --format '{{.Names}}' | grep -E '^'${PREFIX}'[0-9]+-odoo-1$' || true)"
          [ -z "$LIST" ] && { echo "Keine Odoo-Container gefunden – nichts zu diagnostizieren."; exit 0; }
          EXIT=0
          for C in $LIST; do
            echo "==> Diagnose: $C"
            docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E "^$C\\b" || true
            docker inspect "$C" --format 'Cmd: {{.Config.Cmd}}' || true
            docker exec "$C" sh -lc 'ls -l /opt/odoo-init || true'
            STATE="$(docker inspect "$C" --format '{{.State.Health.Status}}' 2>/dev/null || echo unknown)"
            [ "$STATE" = healthy ] || EXIT=1
          done
          [ $EXIT -eq 0 ]
        '''
      }
    }

    stage('Smoke') {
      when { expression { return params.COUNT?.trim() != '' } }
      steps {
        sh '''
          set -eux
          for i in $(seq 1 ${COUNT}); do
            NAME="${PREFIX}${i}"
            if [ -n "${DOMAIN_BASE}" ]; then
              HOST="${NAME}.${DOMAIN_BASE}"
              echo "Smoke (HTTPS bevorzugt): https://${HOST}/web/login"
              curl -sI --resolve "${HOST}:443:127.0.0.1" "https://${HOST}/web/login" | sed -n '1,8p' || true
              echo "Smoke (HTTP Fallback): http://${HOST}/web/login"
              curl -sI --resolve "${HOST}:80:127.0.0.1"  "http://${HOST}/web/login"  | sed -n '1,8p' || true
            else
              PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
              curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,8p' || true
            fi
          done
        '''
      }
    }
  }

  post {
    always {
      // Fix für "set -o pipefail" auf /bin/sh: benutze bash
      sh '''#!/usr/bin/env bash
set -euo pipefail
echo "Build-Dashboard (Kurzinfo):"
docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' | sed -n '1,20p'
'''
    }
  }
}
