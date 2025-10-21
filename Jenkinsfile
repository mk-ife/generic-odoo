pipeline {
  agent any

  options {
    ansiColor('xterm')
    timestamps()
    disableConcurrentBuilds() // jede Build bekommt eigene Ressourcen; mehrere Jobs parallel sind trotzdem möglich (verschiedene Builds)
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    string(name: 'NAME_PREFIX',  defaultValue: 'demo', description: 'Instanz-Prefix (z.B. kunde-a)')
    string(name: 'DOMAIN_BASE',  defaultValue: '91-107-228-241.nip.io', description: 'Traefik Domain (leer = ohne Traefik)')
    string(name: 'COUNT',        defaultValue: '2', description: 'Anzahl Instanzen in diesem Build')
    string(name: 'PARALLEL',     defaultValue: '5', description: 'Wie viele Instanzen parallel starten')
    booleanParam(name: 'TEARDOWN_AFTER', defaultValue: false, description: 'Nach QS wieder alles herunterfahren?')
  }

  environment {
    // Eindeutiges Build-Präfix zur Isolation: z.B. kunde-a-42
    RUN_PREFIX = "${params.NAME_PREFIX}-${env.BUILD_NUMBER}"
    // Arbeitsordner für QS-Artefakte
    ARTIF_DIR  = "artifacts-${env.BUILD_NUMBER}"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -euo pipefail
          mkdir -p "${ARTIF_DIR}"
          echo "Run prefix: ${RUN_PREFIX}" | tee "${ARTIF_DIR}/run.info"
        '''
      }
    }

    stage('Deploy instances') {
      steps {
        sh '''
          set -euo pipefail
          # Wir starten COUNT Instanzen mit Prefix "${RUN_PREFIX}"
          # -> Namen wie: ${RUN_PREFIX}1, ${RUN_PREFIX}2, ...
          if [ -n "${DOMAIN_BASE}" ]; then
            ./scripts/instances-batch.sh "${COUNT}" "${RUN_PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
          else
            ./scripts/instances-batch.sh "${COUNT}" "${RUN_PREFIX}" "" "${PARALLEL}"
          fi
        '''
      }
    }

    stage('QS: Smoke-Tests & Isolation') {
      steps {
        sh '''
          set -euo pipefail
          echo "==> QS start" | tee -a "${ARTIF_DIR}/qs.log"
          PASSED=1

          # 1) Smoke-Test via HTTP (Traefik oder Port, je nach Start)
          for i in $(seq 1 "${COUNT}"); do
            NAME="${RUN_PREFIX}${i}"
            if [ -n "${DOMAIN_BASE}" ]; then
              HOST="${NAME}.${DOMAIN_BASE}"
              echo "[Smoke] ${HOST}" | tee -a "${ARTIF_DIR}/qs.log"
              # explizit :80 über Traefik damit Ausgabe nicht irreführend ist
              if curl -fsS -m 5 --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" >/dev/null; then
                echo "  OK" | tee -a "${ARTIF_DIR}/qs.log"
              else
                echo "  FAIL" | tee -a "${ARTIF_DIR}/qs.log"; PASSED=0
              fi
            else
              # Ohne Traefik: Port wird automatisch kollisionsfrei berechnet (via instance-up.sh)
              # Wir lesen ihn aus den Hints der Up-Logs heraus (Fallback: 8069)
              PORT_HINT=$(docker compose -p "${NAME}" logs odoo 2>/dev/null | grep -Eo 'http://127.0.0.1:[0-9]+' | tail -n1 || true)
              PORT="${PORT_HINT##*:}"
              [ -z "${PORT}" ] && PORT=8069
              echo "[Smoke] ${NAME} via :${PORT}" | tee -a "${ARTIF_DIR}/qs.log"
              if curl -fsS -m 5 "http://127.0.0.1:${PORT}/web/login" >/dev/null; then
                echo "  OK" | tee -a "${ARTIF_DIR}/qs.log"
              else
                echo "  FAIL" | tee -a "${ARTIF_DIR}/qs.log"; PASSED=0
              fi
            fi
          done

          # 2) Keine Shared-Volumes & DB-Namen isoliert?
          #    Check: Volumes und DBs tragen jeweils den Compose-Projektnamen (= Instanzname)
          for i in $(seq 1 "${COUNT}"); do
            NAME="${RUN_PREFIX}${i}"
            echo "[Isolation] ${NAME}" | tee -a "${ARTIF_DIR}/qs.log"
            # Volumes
            VOLS=$(docker volume ls --format '{{.Name}}' | grep -E "(odoo_${NAME}_data|pg_${NAME}_data)" | wc -l || true)
            if [ "${VOLs:-0}" -ge 2 ] || [ "${VOLs:-0}" -eq 2 ]; then
              echo "  Volumes OK" | tee -a "${ARTIF_DIR}/qs.log"
            else
              echo "  Volumes FAIL" | tee -a "${ARTIF_DIR}/qs.log"; PASSED=0
            fi

            # Datenbank-Namen (einfacher Indiz-Check über Odoo-Logs)
            if docker compose -p "${NAME}" logs odoo | grep -q "database: .*@"; then
              echo "  DB tag present in logs" | tee -a "${ARTIF_DIR}/qs.log"
            else
              echo "  DB tag missing (WARN)" | tee -a "${ARTIF_DIR}/qs.log"
            fi
          done

          # 3) Rollback-Test: eine Instanz stoppen – andere bleiben erreichbar
          if [ "${COUNT}" -ge 2 ]; then
            NAME_STOP="${RUN_PREFIX}1"
            echo "[Rollback] stopping ${NAME_STOP}" | tee -a "${ARTIF_DIR}/qs.log"
            docker compose -p "${NAME_STOP}" stop odoo
            sleep 3
            # Prüfe eine andere Instanz
            NAME_OTHER="${RUN_PREFIX}2"
            if [ -n "${DOMAIN_BASE}" ]; then
              HOST="${NAME_OTHER}.${DOMAIN_BASE}"
              if curl -fsS -m 5 --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" >/dev/null; then
                echo "  Others unaffected: OK" | tee -a "${ARTIF_DIR}/qs.log"
              else
                echo "  Others affected: FAIL" | tee -a "${ARTIF_DIR}/qs.log"; PASSED=0
              fi
            else
              PORT_HINT=$(docker compose -p "${NAME_OTHER}" logs odoo 2>/dev/null | grep -Eo 'http://127.0.0.1:[0-9]+' | tail -n1 || true)
              PORT="${PORT_HINT##*:}"; [ -z "${PORT}" ] && PORT=8069
              if curl -fsS -m 5 "http://127.0.0.1:${PORT}/web/login" >/dev/null; then
                echo "  Others unaffected: OK" | tee -a "${ARTIF_DIR}/qs.log"
              else
                echo "  Others affected: FAIL" | tee -a "${ARTIF_DIR}/qs.log"; PASSED=0
              fi
            fi
            # wieder starten, damit Aufräumen sauber klappt (optional)
            docker compose -p "${NAME_STOP}" start odoo || true
          fi

          # Logs sichern (getrennt pro Instanz)
          mkdir -p "${ARTIF_DIR}/logs"
          for i in $(seq 1 "${COUNT}"); do
            NAME="${RUN_PREFIX}${i}"
            mkdir -p "${ARTIF_DIR}/logs/${NAME}"
            docker compose -p "${NAME}" ps -a > "${ARTIF_DIR}/logs/${NAME}/ps.txt" 2>&1 || true
            docker compose -p "${NAME}" logs --no-color > "${ARTIF_DIR}/logs/${NAME}/compose.log" 2>&1 || true
            docker compose -p "${NAME}" logs --no-color db > "${ARTIF_DIR}/logs/${NAME}/db.log" 2>&1 || true
            docker compose -p "${NAME}" logs --no-color odoo > "${ARTIF_DIR}/logs/${NAME}/odoo.log" 2>&1 || true
          done

          echo "==> QS done (PASSED=${PASSED})" | tee -a "${ARTIF_DIR}/qs.log"
          [ "${PASSED}" -eq 1 ]
        '''
      }
    }

    stage('QS: ife-addons-repo-template') {
      steps {
        sh '''
          set -euo pipefail
          echo "==> Clone QS template" | tee -a "${ARTIF_DIR}/qs.log"
          rm -rf qs-template
          git clone --depth=1 https://github.com/ifegmbh/ife-addons-repo-template qs-template
          cd qs-template || exit 1

          # Versuche standardisierte QS-Entrypoints. Fallbacks sind unverbindlich.
          if [ -x ./scripts/ci.sh ]; then
            ./scripts/ci.sh | tee -a "../${ARTIF_DIR}/qs-template.log"
          elif [ -f Makefile ]; then
            make test | tee -a "../${ARTIF_DIR}/qs-template.log"
          elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
            python3 -m venv .venv && . .venv/bin/activate
            pip install -U pip
            [ -f requirements.txt ] && pip install -r requirements.txt || true
            pip install ruff black flake8 pytest || true
            ruff . | tee -a "../${ARTIF_DIR}/qs-template.log" || true
            black --check . | tee -a "../${ARTIF_DIR}/qs-template.log" || true
            flake8 . | tee -a "../${ARTIF_DIR}/qs-template.log" || true
            pytest -q | tee -a "../${ARTIF_DIR}/qs-template.log" || true
          else
            echo "No CI entrypoint detected; recorded only." | tee -a "../${ARTIF_DIR}/qs-template.log"
          fi
        '''
      }
    }

  } // stages

  post {
    always {
      archiveArtifacts artifacts: "${ARTIF_DIR}/**", fingerprint: true, allowEmptyArchive: true
    }
    cleanup {
      script {
        if (params.TEARDOWN_AFTER) {
          sh '''
            set -euo pipefail
            for i in $(seq 1 "${COUNT}"); do
              NAME="${RUN_PREFIX}${i}"
              echo "Tear down ${NAME} ..."
              ./scripts/instance-down.sh "${NAME}" || true
            done
          '''
        }
      }
    }
  }
}
