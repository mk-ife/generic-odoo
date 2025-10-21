pipeline {
  agent any
  options { timestamps() }
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
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

    stage('Ensure init script exists in workspace') {
      steps {
        sh '''
          set -eux
          mkdir -p scripts/odoo-init
          if [ ! -s scripts/odoo-init/entry.sh ]; then
            echo "ERROR: scripts/odoo-init/entry.sh fehlt – bitte ins Repo committen!"
            exit 1
          fi
          ls -l scripts/odoo-init/
        '''
      }
    }

    stage('Sanity: compose render (expect /opt/odoo-init as volume)') {
      steps {
        sh '''
          set -eux
          docker compose config > .compose.rendered.yaml
          sed -n '1,200p' .compose.rendered.yaml

          # Stelle sicher: /opt/odoo-init ist KEIN Host-Bind
          awk '
            $0 ~ /odoo:/ { in_odoo=1 }
            in_odoo && $0 ~ /target: \\/opt\\/odoo-init/ { seen_target=1; next }
            in_odoo && seen_target && $0 ~ /type: bind/ { bad=1 }
            END { if (bad) { print "Found bind mount for /opt/odoo-init (should be volume)"; exit 1 } }
          ' .compose.rendered.yaml
        '''
      }
    }

    stage('Prep init volumes (copy entry.sh into <project>_odoo_init)') {
      steps {
        sh '''
          set -eux
          COUNT="${COUNT:-1}"
          for n in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${n}"

            # Compose generiert Volume-Name automatisch: <project>_<volume> == <NAME>_odoo_init
            VOL="${NAME}_odoo_init"
            echo "==> Preparing volume ${VOL}"
            docker volume create "${VOL}" >/dev/null

            # kopiere aus Workspace ins Volume
            docker run --rm \
              -v "${VOL}:/dst" \
              -v "$PWD/scripts/odoo-init:/src:ro" \
              alpine:3 sh -lc '
                set -e
                test -s /src/entry.sh
                rm -rf /dst/* || true
                cp -r /src/. /dst/
                chmod 755 /dst/entry.sh
                ls -l /dst
              '
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
        echo "==== DIAG: docker ps ===="
        docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"
        echo "==== DIAG: rendered compose (top) ===="
        sed -n '1,200p' .compose.rendered.yaml || true
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
