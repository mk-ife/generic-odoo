pipeline {
  agent any
  options { timestamps() }
  parameters {
    string(name: 'COUNT', defaultValue: '1', description: 'Wie viele Instanzen?')
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Präfix für Instanznamen')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Traefik Domain-Basis')
    string(name: 'PARALLEL', defaultValue: '1', description: 'Parallel gestartete Jobs')
  }
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Ensure docker compose CLI') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version
        '''
      }
    }

    stage('Hotfix: ensure entry.sh exists') {
      steps {
        sh '''
          set -eux
          mkdir -p scripts/odoo-init
          if [ ! -s scripts/odoo-init/entry.sh ]; then
            cat > scripts/odoo-init/entry.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DESIRED_DB="${DESIRED_DB:-${POSTGRES_DB:-${COMPOSE_PROJECT_NAME:-odoo}_db}}"
ODOO_DB_ARGS=(--db_host "${DB_HOST}" --db_port "${DB_PORT}" --db_user "${DB_USER}" --db_password "${DB_PASSWORD}")
echo "[odoo-init] DB=${DESIRED_DB} on ${DB_HOST}:${DB_PORT} (user=${DB_USER})"
for i in {1..180}; do
  if bash -lc "exec 3<>/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
    echo "[odoo-init] postgres reachable"; break; fi; sleep 1; done
tries=0
until [ $tries -ge 5 ]; do
  set +e
  echo "[odoo-init] init attempt $((tries+1))/5: odoo -d ${DESIRED_DB} -i base --stop-after-init ${ODOO_DB_ARGS[*]}"
  odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}" -i base --stop-after-init
  rc=$?; set -e
  [ $rc -eq 0 ] && { echo "[odoo-init] base installed (or already up-to-date)"; break; }
  tries=$((tries+1)); sleep 5
done
echo "[odoo-init] starting odoo httpd..."
exec odoo "${ODOO_DB_ARGS[@]}" -d "${DESIRED_DB}"
BASH
            chmod +x scripts/odoo-init/entry.sh
          fi
          ls -l scripts/odoo-init/
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          cd "$WORKSPACE"

          # Compose muss deinen Ordner als /opt/odoo-init mounten und das Script starten
          # (deine docker-compose.yml sollte bereits haben:)
          #   volumes:
          #     - ./scripts/odoo-init:/opt/odoo-init:ro
          #   command: ["/bin/bash","-lc","/opt/odoo-init/entry.sh"]

          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }
  }
}
