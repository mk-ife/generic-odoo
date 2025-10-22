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
  }

  environment {
    // docker compose CLI ins Workspace installieren (falls auf Agent nicht vorhanden)
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    // Quelle für /opt/odoo-init Bind-Mount
    ODOO_INIT_SRC = "${WORKSPACE}/scripts/odoo-init"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
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

    stage('Sanity: compose render + Mount prüfen') {
      steps {
        sh '''
          set -eux
          # gerendertes compose einmal anzeigen
          docker compose config | tee .compose.rendered.yaml | sed -n '1,200p'

          # Erwartung: Bind-Mount von ${ODOO_INIT_SRC} -> /opt/odoo-init
          grep -q "target: /opt/odoo-init" .compose.rendered.yaml
          grep -q "source: ${ODOO_INIT_SRC}" .compose.rendered.yaml || echo "Hinweis: compose zeigt abs. Pfad; ok solange /opt/odoo-init target stimmt."
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
          "ODOO_INIT_SRC=${env.ODOO_INIT_SRC}"
        ]) {
          sh '''
            set -eux
            cd "${WORKSPACE}"
            ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true  # wir brechen nicht sofort ab -> Diagnose
          '''
        }
      }
    }

    stage('Diagnose (bei Unhealthy)') {
      steps {
        sh '''
          set -eux
          # finde alle gestarteten Odoo-Container des Jobs
          LIST="$(docker ps -a --format '{{.Names}}' | grep -E '^'${PREFIX}'[0-9]+-odoo-1$' || true)"
          if [ -z "$LIST" ]; then
            echo "Keine Odoo-Container gefunden – nichts zu diagnostizieren."
            exit 0
          fi

          EXIT=0
          for C in $LIST; do
            echo "==> Diagnose für Container: $C"
            docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E "^$C\\b" || true

            # Inspect: Mounts + Command
            echo "--- docker inspect (Mounts, Config.Cmd) ---"
            docker inspect "$C" --format '{{json .Mounts}}' | jq '.' || true
            docker inspect "$C" --format 'Cmd: {{.Config.Cmd}}' || true

            # Prüfe, ob /opt/odoo-init gemountet ist und entry.sh ausführbar ist
            echo "--- Dateien in /opt/odoo-init ---"
            docker exec "$C" sh -lc 'ls -l /opt/odoo-init || true'

            echo "--- entry.sh Inhalt (erste 80 Zeilen) ---"
            docker exec "$C" sh -lc 'sed -n "1,80p" /opt/odoo-init/entry.sh || true'

            echo "--- Shell-Syntax-Check ---"
            docker exec "$C" sh -lc 'bash -n /opt/odoo-init/entry.sh || echo "bash -n meldet Fehler"; true'

            echo "--- Env in Container (relevant) ---"
            docker exec "$C" sh -lc 'env | egrep "DB_HOST|DB_PORT|DB_USER|DB_PASSWORD|DESIRED_DB|COMPOSE_PROJECT_NAME" || true'

            echo "--- letze 200 Zeilen Odoo-Log ---"
            PNAME="${C%-odoo-1}"   # Compose-Projektname
            docker compose -p "$PNAME" logs --tail=200 odoo || true

            # Health prüfen
            STATE="$(docker inspect "$C" --format '{{.State.Health.Status}}' 2>/dev/null || echo 'unknown')"
            echo "Health: $STATE"
            if [ "$STATE" != "healthy" ]; then
              EXIT=1
            fi
          done

          # wenn irgendwer ungesund war, als Fehler markieren -> Smoke wird dann übersprungen
          if [ $EXIT -ne 0 ]; then
            echo "Mindestens eine Odoo-Instanz ist unhealthy."
            exit 1
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
