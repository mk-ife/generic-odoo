pipeline {
  agent any

  options {
    skipDefaultCheckout(true)
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    string(name: 'COUNT',       defaultValue: '1',                     description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX',      defaultValue: 'demo',                  description: 'Instanz-Prefix, z.B. "kunde-a-"')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'leer = ohne Traefik; sonst Traefik-Domain-Basis')
    string(name: 'PARALLEL',    defaultValue: '1',                     description: 'Parallel gestartete Jobs')
  }

  environment {
    // docker compose CLI ins Workspace installieren (falls auf Agent nicht vorhanden)
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    // WICHTIG: relativer Pfad (sichtbar für Docker-Daemon beim Bind-Mount)
    ODOO_INIT_SRC = "./scripts/odoo-init"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -ex
          # compose v2 CLI verfügbar machen
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

          # Startet COUNT Instanzen mit PREFIX[, DOMAIN_BASE] und der gewünschten Parallelität
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
              echo "Smoke via Traefik: http://${HOST}/web/login"
              curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,12p'
            else
              PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
              test -n "${PORT}"
              echo "Smoke direct: http://127.0.0.1:${PORT}/web/login"
              curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,12p'
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
            docker compose -p "${NAME}" ps > "logs_${NAME}_ps.txt" 2>&1 || true
            docker compose -p "${NAME}" logs --tail=300 odoo > "logs_${NAME}_odoo.txt" 2>&1 || true
            docker compose -p "${NAME}" logs --tail=300 db   > "logs_${NAME}_db.txt"   2>&1 || true
          done
        '''
        archiveArtifacts artifacts: 'logs_*.txt', fingerprint: true, onlyIfSuccessful: false
      }
    }
  }

  post {
    // Dieser Block läuft IMMER – auch bei Fehlern, und ZUERST sammeln wir Logs, DANN räumen wir auf.
    always {
      // 1) Logs vor Cleanup einsammeln (auch wenn Stages geskippt wurden)
      sh '''
        set +e
        COUNT="${COUNT}"
        PREFIX="${PREFIX}"

        rm -f post_logs_*.txt || true

        for i in $(seq 1 "${COUNT}"); do
          NAME="${PREFIX}${i}"
          # ps + komplette Logs + gezielt odoo/db
          docker compose -p "${NAME}" ps > "post_logs_${NAME}_ps.txt" 2>&1 || true
          docker compose -p "${NAME}" logs --no-color > "post_logs_${NAME}_all.txt" 2>&1 || true
          docker compose -p "${NAME}" logs --tail=500 odoo > "post_logs_${NAME}_odoo.txt" 2>&1 || true
          docker compose -p "${NAME}" logs --tail=500 db   > "post_logs_${NAME}_db.txt"   2>&1 || true
        done
      '''
      archiveArtifacts artifacts: 'post_logs_*.txt', fingerprint: true, onlyIfSuccessful: false

      // 2) Danach sauberer Cleanup (Container + Volumes)
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
