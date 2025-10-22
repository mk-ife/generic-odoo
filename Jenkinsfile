pipeline {
  agent any
  options { skipDefaultCheckout(true); timestamps(); timeout(time: 30, unit: 'MINUTES') }

  parameters {
    string(name: 'COUNT',       defaultValue: '1',    description: 'Anzahl Instanzen')
    string(name: 'PREFIX',      defaultValue: 'demo', description: 'Prefix, z.B. kunde-a-')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'leer = ohne Traefik')
    string(name: 'PARALLEL',    defaultValue: '1',    description: 'Parallelität (1 = seriell)')
  }

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    ODOO_INIT_SRC = "${WORKSPACE}/scripts/odoo-init"   // Quelle für entry.sh (im Repo)
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

    stage('Sanity: compose render (expect volume /opt/odoo-init)') {
      steps {
        sh '''
          set -eux
          docker compose config | tee .compose.rendered.yaml | sed -n '1,200p'
          grep -q "target: /opt/odoo-init" .compose.rendered.yaml
          # wichtig: Kein bind auf /opt/odoo-init in der Compose-Datei!
          ! grep -q "\\- type: bind\\s*$" -n .compose.rendered.yaml || { echo "FATAL: /opt/odoo-init darf kein bind sein"; exit 1; }
        '''
      }
    }

    stage('Prep init volumes (copy entry.sh into <NAME>_odoo_init)') {
      steps {
        sh '''
          set -eux
          COUNT="${COUNT:-1}"
          for i in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${i}"
            VOL="${NAME}_odoo_init"
            echo "==> Preparing volume ${VOL}"
            docker volume create "${VOL}"
            # Wir kopieren vom Jenkins-Workspace in das Volume (Host-unabhängig)
            docker run --rm \
              -v "${VOL}:/dst" \
              -v "${ODOO_INIT_SRC}:/src:ro" \
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
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true
        '''
      }
    }

    stage('Diagnose (bei Unhealthy)') {
      steps {
        sh '''
          set -eux
          LIST="$(docker ps -a --format '{{.Names}}' | grep -E '^'${PREFIX}'[0-9]+-odoo-1$' || true)"
          [ -n "${LIST}" ] || { echo "Keine Odoo-Container gefunden."; exit 0; }

          EXIT=0
          for C in $LIST; do
            echo "==> Diagnose für ${C}"
            docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E "^${C}\\b" || true
            echo "--- Inspect Mounts ---"
            docker inspect "${C}" --format '{{range .Mounts}}{{println .Type .Source "->" .Destination}}{{end}}' || true
            echo "--- Inspect Cmd ---"
            docker inspect "${C}" --format 'Cmd: {{.Config.Cmd}}' || true

            PNAME="${C%-odoo-1}"
            echo "--- Log (odoo, last 200) ---"
            docker compose -p "${PNAME}" logs --tail=200 odoo || true

            STATE="$(docker inspect "${C}" --format '{{.State.Health.Status}}' 2>/dev/null || echo unknown)"
            echo "Health: ${STATE}"
            if [ "${STATE}" != "healthy" ]; then EXIT=1; fi
          done

          if [ ${EXIT} -ne 0 ]; then
            echo "Mindestens eine Instanz ist unhealthy."; exit 1
          fi
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
              echo "Smoke: ${HOST}"
              curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,8p'
            else
              PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
              echo "Smoke: http://127.0.0.1:${PORT}/web/login"
              curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,8p'
            fi
          done
        '''
      }
    }
  }
}
