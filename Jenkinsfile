pipeline {
  agent any
  options { timestamps() }
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    // WICHTIG: Override für CI aktivieren
    COMPOSE_FILE  = "docker-compose.yml:docker-compose.ci.yml"
  }
  parameters {
    string(name: 'COUNT',       defaultValue: '1',                        description: 'Wie viele Instanzen?')
    string(name: 'PREFIX',      defaultValue: 'demo',                     description: 'Präfix (demo => demo1, …)')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io',    description: 'Traefik Domain-Basis')
    string(name: 'PARALLEL',    defaultValue: '1',                        description: 'Parallel gestartete Jobs')
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

    stage('Ensure init script (entry.sh) exists') {
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
  if bash -lc "exec 3<>/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then echo "[odoo-init] postgres reachable"; break; fi
  sleep 1
done
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
          fi
          chmod +x scripts/odoo-init/entry.sh
          ls -l scripts/odoo-init/
        '''
      }
    }

    stage('Sanity (compose render incl. CI override)') {
      steps {
        sh '''
          set -eux
          docker compose config > .compose.rendered.yaml
          sed -n '1,200p' .compose.rendered.yaml

          # WICHTIG: Mit CI-Override muss das Ziel /opt/odoo-init ein Volume sein:
          grep -q 'target: /opt/odoo-init' .compose.rendered.yaml
          grep -q 'type: volume' .compose.rendered.yaml
          # Standard-Projektname ist der Ordnername -> generic-odoo
          grep -q 'source: odoo_init_generic-odoo' .compose.rendered.yaml || true
        '''
      }
    }

    stage('Prep init volumes (copy entry.sh into per-project volume)') {
      steps {
        sh '''
          set -eux
          COUNT="${COUNT:-1}"
          for n in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${n}"
            VOL="odoo_init_${NAME}"
            echo "==> Preparing volume ${VOL}"
            docker volume create "${VOL}" >/dev/null
            # Inhalt reinkopieren (Rechte sicherstellen)
            docker run --rm \
              -v "${VOL}:/dst" \
              -v "$PWD/scripts/odoo-init:/src:ro" \
              alpine:3 sh -lc 'set -e; rm -rf /dst/*; cp -r /src/. /dst/; chmod 755 /dst/entry.sh; ls -l /dst'
          done
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
          echo "==> Running containers:"
          docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"
        '''
      }
    }

    stage('Smoke (kurz)') {
      steps {
        sh '''
          set -eux
          for n in $(seq 1 "${COUNT}"); do
            host="${PREFIX}${n}.${DOMAIN_BASE}"
            echo "Smoke: ${host}"
            for i in $(seq 1 180); do
              if curl -fsSI --resolve "${host}:80:127.0.0.1" "http://${host}/web/login" | head -n1 | grep -E "200 OK|302 Found" >/dev/null; then
                echo "OK: ${host} antwortet."; break
              fi
              sleep 1
            done
            curl -sI --resolve "${host}:80:127.0.0.1" "http://${host}/web/login" | sed -n '1,5p' || true
          done
        '''
      }
    }
  }

  post {
    failure {
      sh '''
        set -eux
        echo "==== DIAG: docker compose ps (global) ===="
        docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"
        echo "==== DIAG: rendered compose (top) ===="
        sed -n '1,160p' .compose.rendered.yaml || true
        echo "==== DIAG: per-project logs ===="
        for n in $(seq 1 "${COUNT}"); do
          p="${PREFIX}${n}"
          echo "---- ${p} ps ----"
          docker compose -p "${p}" ps || true
          echo "---- ${p} logs odoo (tail 200) ----"
          docker compose -p "${p}" logs --tail=200 odoo || true
          echo "---- ${p} logs db (tail 100) ----"
          docker compose -p "${p}" logs --tail=100 db || true
        done
      '''
    }
  }
}
