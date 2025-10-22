pipeline {
  agent any
  options {
    skipDefaultCheckout(true)
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }

  /***************
   * Parameter
   ***************/
  parameters {
    // Bestehende
    string(name: 'COUNT',       defaultValue: '1',    description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX',      defaultValue: 'demo', description: 'Instanz-Prefix, z.B. "kunde-a-"')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'leer = ohne Traefik; sonst Traefik-Domain-Basis')
    string(name: 'PARALLEL',    defaultValue: '1',    description: 'Parallel gestartete Jobs')

    // NEU: Zugangsdaten-Auswahl (nur erfasst/ausgegeben – dein Deploy bleibt unverändert)
    choice(name: 'AUTH_MODE', choices: ['none', 'usernamePassword', 'sshKey'], description: 'Zugangsdaten-Quelle für Dashboard (optional)')
    credentials(name: 'AUTH_CREDENTIALS_ID', defaultValue: '', description: 'Jenkins-Credentials-ID (User/Pass ODER SSH-Key) für Dashboard')

    // NEU: Dashboard-Steuerung
    booleanParam(name: 'INCLUDE_SECRETS_IN_DASHBOARD', defaultValue: false, description: '⚠️ Zugangsdaten in Dashboard-Dateien aufnehmen (nie ins Log)')

    // NEU: HTTPS/Let’s Encrypt (Traefik wird NICHT angefasst, nur optionaler Start falls compose-File vorhanden)
    booleanParam(name: 'FORCE_HTTPS', defaultValue: true, description: 'HTTPS-Router aktivieren (Traefik + Let’s Encrypt)')
    string(name: 'LE_EMAIL', defaultValue: 'admin@example.com', description: 'E-Mail für Let’s Encrypt (ACME)')
  }

  environment {
    // docker compose CLI ins Workspace installieren (falls auf Agent nicht vorhanden)
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_CLI   = "${WORKSPACE}/.docker/cli-plugins/docker-compose"
    // Quelle für /opt/odoo-init Bind-Mount
    ODOO_INIT_SRC = "${WORKSPACE}/scripts/odoo-init"

    // nur für Labels/Overlays (brechen nichts wenn ungenutzt)
    TRAEFIK_ENABLE = "${params.DOMAIN_BASE ? 'true' : 'false'}"
    TRAEFIK_TLS    = "${params.FORCE_HTTPS ? 'true' : 'false'}"
    CERT_RESOLVER  = "le"
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

    // NEU (optional + no-op wenn file nicht existiert): Traefik mit LE starten
    stage('Optional: Ensure Traefik (HTTPS)') {
      when {
        allOf {
          expression { return params.FORCE_HTTPS }
          expression { return fileExists('docker-compose.traefik.yml') }
        }
      }
      steps {
        sh '''
          set -eux
          mkdir -p traefik
          [ -f traefik/acme.json ] || { touch traefik/acme.json; chmod 600 traefik/acme.json; }
          export LE_EMAIL="${LE_EMAIL}"
          docker compose -f docker-compose.traefik.yml up -d
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
          "ODOO_INIT_SRC=${env.ODOO_INIT_SRC}",
          "LE_EMAIL=${params.LE_EMAIL}",
          "TRAEFIK_TLS=${env.TRAEFIK_TLS}",
          "CERT_RESOLVER=${env.CERT_RESOLVER}"
        ]) {
          // Wir rühren deinen Start-Ablauf nicht an
          sh '''
            set -eux
            cd "${WORKSPACE}"
            ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}" || true  # brechen nicht sofort ab -> Diagnose
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
            docker ps -a --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' | grep -E "^$C\\b" || true

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
              echo "Smoke(HTTP): ${HOST}"
              curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,8p' || true
              if [ "${TRAEFIK_TLS}" = "true" ]; then
                echo "Smoke(HTTPS): ${HOST}"
                curl -skI --resolve "${HOST}:443:127.0.0.1" "https://${HOST}/web/login" | sed -n '1,8p' || true
              fi
            else
              PORT="$(docker compose -p "${NAME}" port odoo 8069 | sed 's/.*://')"
              echo "Smoke: http://127.0.0.1:${PORT}/web/login"
              curl -sI "http://127.0.0.1:${PORT}/web/login" | sed -n '1,8p' || true
            fi
          done
        '''
      }
    }

    // NEU: Dashboard (CSV/HTML) – enthält optional die Zugangsdaten (keine Ausgabe im Log!)
    stage('Dashboard') {
      steps {
        withCredentials([
          usernamePassword(credentialsId: params.AUTH_CREDENTIALS_ID, usernameVariable: 'AUTH_USER', passwordVariable: 'AUTH_PASS')
        ]) {
          sh '''
            set -euo pipefail
            mkdir -p build
            CSV="build/dashboard.csv"
            HTML="build/dashboard.html"
            echo "name,url,db_name,cred_mode,cred_id,username,password" > "$CSV"

            for i in $(seq 1 ${COUNT}); do
              NAME="${PREFIX}${i}"
              HOST="${NAME}.${DOMAIN_BASE}"
              URL="http://${HOST}/web"
              [ "${TRAEFIK_TLS}" = "true" ] && URL="https://${HOST}/web"
              DB="${NAME}_db"

              USER_DATA=""
              PASS_DATA=""
              if [ "${INCLUDE_SECRETS_IN_DASHBOARD}" = "true" ] && [ "${AUTH_MODE}" = "usernamePassword" ] && [ -n "${AUTH_CREDENTIALS_ID}" ]; then
                USER_DATA="${AUTH_USER:-}"
                PASS_DATA="${AUTH_PASS:-}"
              fi

              echo "${NAME},${URL},${DB},${AUTH_MODE},${AUTH_CREDENTIALS_ID},${USER_DATA},${PASS_DATA}" >> "$CSV"
            done

            {
              echo "<html><head><meta charset='utf-8'><title>Odoo Demo Dashboard</title>"
              echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px}</style>"
              echo "</head><body><h1>Odoo Demo Dashboard</h1>"
              echo "<table><tr><th>Name</th><th>URL</th><th>DB</th><th>Cred-Mode</th><th>Cred-ID</th><th>User</th><th>Password</th></tr>"
              tail -n +2 "$CSV" | while IFS=, read -r n u d cm cid user pass; do
                echo "<tr><td>${n}</td><td><a href='${u}'>${u}</a></td><td>${d}</td><td>${cm}</td><td>${cid}</td><td>${user}</td><td>${pass}</td></tr>"
              done
              echo "</table></body></html>"
            } > "$HTML"
          '''
        }
        archiveArtifacts artifacts: 'build/dashboard.*', fingerprint: true
      }
    }
  }

  post {
    always {
      sh '''
        set -euo pipefail
        echo "==> Running containers:"
        docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'
      '''
    }
  }
}
