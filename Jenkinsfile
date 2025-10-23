pipeline {
  agent any
  options { timestamps() }
  parameters {
    string(name: 'COUNT',       defaultValue: '1',                description: 'Wieviele Instanzen?')
    string(name: 'PREFIX',      defaultValue: 'demo',             description: 'Instanz-Präfix')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Basisdomain für Traefik')
    string(name: 'PARALLEL',    defaultValue: '1',                description: 'Wie viele parallel starten')
  }
  environment { DOCKER_CONFIG = "${WORKSPACE}/.docker" }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Sanity (compose render, nur Info)') {
      steps {
        sh '''
          set -eux
          docker compose -f docker-compose.yml -f docker-compose.init.yml config | tee .compose.rendered.yaml >/dev/null
          sed -n '1,200p' .compose.rendered.yaml
          echo "INFO: /opt/odoo-init kommt über named volume <NAME>_odoo_init"
        '''
      }
    }
    stage('Deploy batch (nie failen)') {
      steps {
        sh '''
          set -eux
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true
          echo "==> Running containers:"
          docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'
        '''
      }
    }
    stage('Diagnose (immer)') {
      steps {
        sh '''
          set -eux
          LIST="$(docker ps -a --format '{{.Names}}' | grep -E "^${PREFIX}[0-9]+-odoo-1$" || true)"
          if [ -n "${LIST}" ]; then
            for c in $LIST; do
              echo "==> Diagnose für Container: $c"
              base="${c%%-odoo-1}"
              docker ps -a --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' | grep -E "^${c}\\b" || true
              echo "--- docker inspect (Cmd/Mounts) ---"
              docker inspect "$c" --format 'Cmd: {{.Config.Cmd}}' || true
              docker inspect "$c" --format '{{json .Mounts}}' || true
              echo "--- /opt/odoo-init Inhalt (im Container) ---"
              docker exec "$c" sh -lc 'ls -l /opt/odoo-init || true' || true
              echo "--- entry.sh (erste 80 Zeilen) ---"
              docker exec "$c" sh -lc 'sed -n "1,80p" /opt/odoo-init/entry.sh || true' || true
              echo "--- letzte Odoo-Logs ---"
              docker compose -p "$base" logs --tail=200 odoo || true
            done
          else
            echo "WARN: Keine odoo-Container mit Präfix ${PREFIX} gefunden."
          fi
        '''
      }
    }
    stage('Smoke (immer)') {
      steps {
        sh '''
          set -eux
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
