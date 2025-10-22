pipeline {
  agent any
  options { timestamps() }
  parameters {
    string(name: 'COUNT', defaultValue: '1', description: 'Wieviele Instanzen?')
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Instanz-Präfix (pro Kunde anpassbar)')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Basisdomain für Traefik')
    string(name: 'PARALLEL', defaultValue: '1', description: 'Wie viele parallel starten')
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

    stage('Sanity: compose render (WARN wenn bind auf /opt/odoo-init)') {
      steps {
        sh '''
          set -eux
          docker compose config | tee .compose.rendered.yaml >/dev/null
          sed -n '1,200p' .compose.rendered.yaml
          if grep -q "target: /opt/odoo-init" .compose.rendered.yaml && grep -q "\\- type: bind\\s*$" -n .compose.rendered.yaml; then
            echo "WARN: /opt/odoo-init ist als bind gemountet. Bitte Override fixen!"
          else
            echo "OK: /opt/odoo-init ist kein bind."
          fi
        '''
      }
    }

    stage('Prep init volumes (copy entry.sh into <NAME>_odoo_init)') {
      steps {
        sh '''
          set -eux
          COUNT="${COUNT}"
          for n in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${n}"
            VOL="${NAME}_odoo_init"
            echo "==> Preparing volume ${VOL}"
            docker volume create "${VOL}"
            # entry.sh aus Repo in das Volume kopieren:
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
          docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'
        '''
      }
    }

    stage('Diagnose (bei Unhealthy)') {
      steps {
        sh '''
          set -eux
          LIST="$(docker ps -a --format '{{.Names}}' | grep -E "^${PREFIX}[0-9]+-odoo-1$" || true)"
          if [ -n "${LIST}" ]; then
            for c in $LIST; do
              echo "==> Diagnose für Container: $c"
              docker ps -a --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' | grep -E "^${c}\\b" || true
              echo "--- docker inspect (Cmd/Mounts) ---"
              docker inspect "$c" --format 'Cmd: {{.Config.Cmd}}' || true
              docker inspect "$c" --format '{{json .Mounts}}' || true
              echo "--- /opt/odoo-init Inhalt ---"
              docker exec "$c" sh -lc 'ls -l /opt/odoo-init || true' || true
              echo "--- letzte Odoo-Logs ---"
              docker compose -p "${c%%-odoo-1}" logs --tail=200 odoo || true
            done
          fi
        '''
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -eux
          COUNT="${COUNT}"
          for n in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${n}"
            HOST="${NAME}.${DOMAIN_BASE}"
            echo "Test: curl -sI --resolve '${HOST}:80:127.0.0.1' http://${HOST}/web/login | sed -n '1,5p'"
            curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,5p' || true
          done
        '''
      }
    }
  }
}
