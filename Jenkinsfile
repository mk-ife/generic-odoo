pipeline {
  agent any

  options {
    skipDefaultCheckout(true)
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    string(name: 'COUNT',       defaultValue: '1',                    description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX',      defaultValue: 'demo',                 description: 'Instanz-Prefix, z.B. "kunde-a-"')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'leer = ohne Traefik; sonst Traefik-Domain-Basis')
    string(name: 'PARALLEL',    defaultValue: '1',                    description: 'Parallel gestartete Jobs')
  }

  environment {
    // docker compose CLI ins Workspace installieren (falls auf Agent nicht vorhanden)
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    // WICHTIG: relativer Pfad statt absolutem WORKSPACE-Pfad (sichtbar für Docker-Daemon)
    ODOO_INIT_SRC = "./scripts/odoo-init"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -ex
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$COMPOSE_CLI" ]; then
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$COMPOSE_CLI"
            chmod +x "$COMPOSE_CLI"
          fi
          docker compose version

          # Init-Skript muss existieren und ausführbar sein
          test -s "${ODOO_INIT_SRC}/entry.sh" || { echo "FEHLT: ${ODOO_INIT_SRC}/entry.sh"; exit 1; }
          chmod +x "${ODOO_INIT_SRC}/entry.sh"
        '''
      }
    }

    stage('Up (batch)') {
      steps {
        sh '''
          set -ex
          COUNT="${COUNT}"
          PREFIX="${PREFIX}"
          DOMAIN_BASE="${DOMAIN_BASE}"
          PARALLEL="${PARALLEL}"
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }

    stage('Smoke tests') {
      steps {
        sh '''
          set -ex
          COUNT="${COUNT}"
          PREFIX="${PREFIX}"
          DOMAIN_BASE="${DOMAIN_BASE}"

          for i in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${i}"
            echo "== Smoke: ${NAME}"
            if [ -n "${DOMAIN_BASE}" ]; then
              HOST="${NAME}.${DOMAIN_BASE}"
              curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,8p'
            else
              PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
              test -n "${PORT}"
              curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,8p'
            fi
          done
        '''
      }
    }

    stage('Collect logs') {
      steps {
        sh '''
          set -ex
          COUNT="${COUNT}"
          PREFIX="${PREFIX}"
          rm -f logs_*.txt || true
          for i in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${i}"
            docker compose -p "${NAME}" ps > "logs_${NAME}_ps.txt" || true
            docker compose -p "${NAME}" logs --tail=300 odoo > "logs_${NAME}_odoo.txt" || true
            docker compose -p "${NAME}" logs --tail=300 db   > "logs_${NAME}_db.txt"   || true
          done
        '''
        archiveArtifacts artifacts: 'logs_*.txt', fingerprint: true, onlyIfSuccessful: false
      }
    }
  }

  post {
    always {
      sh '''
        set +e
        COUNT="${COUNT}"
        PREFIX="${PREFIX}"
        for i in $(seq 1 "${COUNT}"); do
          NAME="${PREFIX}${i}"
          echo "== Cleanup: ${NAME}"
          ./scripts/instance-down.sh "${NAME}" || true
        done
      '''
    }
  }
}
