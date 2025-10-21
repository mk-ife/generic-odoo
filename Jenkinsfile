pipeline {
  agent any

  options {
    // Fix für ältere Jenkins-Setups ohne options { ansiColor('xterm') }
    wrap([$class: 'AnsiColorBuildWrapper', colorMapName: 'xterm'])
    timestamps()
    disableConcurrentBuilds()      // keine parallelen Builds desselben Jobs
    timeout(time: 45, unit: 'MINUTES')
  }

  parameters {
    // Wie viele Instanzen (demo1..demoN)
    string(name: 'COUNT', defaultValue: '2', description: 'Anzahl der Odoo-Instanzen')
    // Namenspräfix (demo -> demo1, demo2 …)
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Präfix für Instanznamen')
    // Traefik-Domain-Basis; leer = ohne Traefik/Portbetrieb
    string(name: 'DOMAIN_BASE', defaultValue: '', description: 'z.B. 91-107-228-241.nip.io (leer = ohne Traefik)')
    // Parallele Starts im Batch
    string(name: 'PARALLEL', defaultValue: '5', description: 'Parallel gestartete Instanzen beim Batch')
    // Kunde/Label (fließt in Logs/Artefakte ein)
    string(name: 'CUSTOMER', defaultValue: '', description: 'Optionaler Kundenname/Label')
    // QS schalten
    booleanParam(name: 'RUN_QS', defaultValue: true, description: 'Qualitätssicherung/Smoke-Tests ausführen')
    // Nach QS wieder abbauen?
    booleanParam(name: 'TEARDOWN', defaultValue: false, description: 'Instanzen nach Pipeline wieder entfernen')
  }

  environment {
    RUN_TAG   = "${env.JOB_NAME}-${env.BUILD_NUMBER}"
    WORKAREA  = "work-${env.BUILD_NUMBER}"
    LOGDIR    = "logs-${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout generic-odoo') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD || true'
      }
    }

    stage('Fetch QS Template (ife-addons-repo-template)') {
      steps {
        dir('qa-template') {
          // read-only clone, kein Submodul nötig
          git branch: 'main', url: 'https://github.com/ifegmbh/ife-addons-repo-template'
        }
      }
    }

    stage('Start Instances') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p "${WORKAREA}" "${LOGDIR}"
          chmod +x scripts/*.sh

          echo "[INFO] Batch-Start: COUNT=${COUNT} PREFIX=${PREFIX} DOMAIN_BASE=${DOMAIN_BASE} PARALLEL=${PARALLEL}"
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"

          echo "[INFO] Batch-Start abgeschlossen."
        '''
      }
    }

    stage('Smoke & QS') {
      when { expression { return params.RUN_QS } }
      steps {
        sh '''
          set -euo pipefail
          echo "[INFO] QS/Smoke-Tests starten …"
          OK=1

          if [[ -n "${DOMAIN_BASE}" ]]; then
            # Traefik-Variante: HTTP :80, lokale Weiterleitung via --resolve für CI-Agent
            for i in $(seq 1 "${COUNT}"); do
              NAME="${PREFIX}${i}"
              HOST="$(echo "${NAME}.${DOMAIN_BASE}" | tr '[:upper:]' '[:lower:]')"
              echo "[TEST] ${HOST} /web/login"
              # 2xx/3xx genügt
              if ! curl -fsS -m 5 --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" > /dev/null ; then
                echo "[ERROR] Smoke-Test fehlgeschlagen: ${HOST}"
                OK=0
              fi
            done
          else
            # Port-Variante (ohne Traefik): Ports werden durch instance-up auto-berechnet
            # Wir rekonstruieren hier die erwarteten Ports identisch zur Logik in instance-up.sh
            for i in $(seq 1 "${COUNT}"); do
              NAME="${PREFIX}${i}"
              NAME_LC="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
              NAME_LC="$(echo "${NAME_LC}" | sed 's/^[^a-z0-9]//')"
              # OFFSET = (cksum % 200)
              OFFSET=$(echo -n "${NAME_LC}" | cksum | awk '{print $1 % 200}')
              PORT=$((8069 + OFFSET))

              echo "[TEST] ${NAME_LC} -> http://127.0.0.1:${PORT}/web/login"
              if ! curl -fsS -m 5 "http://127.0.0.1:${PORT}/web/login" > /dev/null ; then
                echo "[ERROR] Smoke-Test fehlgeschlagen: ${NAME_LC} Port=${PORT}"
                OK=0
              fi
            done
          fi

          # (Platzhalter) weitere QS aus qa-template integrieren:
          # z.B. Python/linters/tests – hier nur demonstrativ:
          echo "[INFO] Starte placeholder QS aus qa-template (falls vorhanden)…"
          if [[ -f qa-template/run_qs.sh ]]; then
            bash qa-template/run_qs.sh || OK=0
          else
            echo "[WARN] qa-template/run_qs.sh nicht gefunden – übersprungen."
          fi

          if [[ "${OK}" != "1" ]]; then
            echo "[FAIL] QS/Smoke-Tests fehlgeschlagen."
            exit 2
          fi
          echo "[OK] QS/Smoke-Tests bestanden."
        '''
      }
    }

    stage('Logs sammeln') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p "${LOGDIR}"

          for i in $(seq 1 "${COUNT}"); do
            NAME="${PREFIX}${i}"
            NAME_LC="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
            NAME_LC="$(echo "${NAME_LC}" | sed 's/^[^a-z0-9]//')"
            echo "[INFO] Sammle Logs für ${NAME_LC} …"
            # compose logs in Datei; Fehler nicht fatal
            docker compose -p "${NAME_LC}" logs --no-color > "${LOGDIR}/${NAME_LC}.log" 2>&1 || true
          done

          # kleine QS-Zusammenfassung
          {
            echo "RUN_TAG=${RUN_TAG}"
            echo "CUSTOMER=${CUSTOMER}"
            echo "COUNT=${COUNT}"
            echo "PREFIX=${PREFIX}"
            echo "DOMAIN_BASE=${DOMAIN_BASE}"
            echo "PARALLEL=${PARALLEL}"
            date -Iseconds
          } > "${LOGDIR}/run-meta.txt"
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: "${LOGDIR}/**", allowEmptyArchive: true
    }
    success {
      echo "Pipeline erfolgreich – Umgebungen bleiben aktiv (TEARDOWN=${params.TEARDOWN})."
    }
    unsuccessful {
      echo "Pipeline fehlgeschlagen – Logs archiviert. TEARDOWN=${params.TEARDOWN}"
    }
    cleanup {
      script {
        if (params.TEARDOWN) {
          sh '''
            set -euo pipefail
            echo "[CLEANUP] TearDown aktiviert – entferne Instanzen."
            for i in $(seq 1 "${COUNT}"); do
              NAME="${PREFIX}${i}"
              ./scripts/instance-down.sh "${NAME}" || true
            done
          '''
        } else {
          echo "[CLEANUP] TearDown aus – Instanzen bleiben für manuelle QS stehen."
        }
      }
    }
  }
}
