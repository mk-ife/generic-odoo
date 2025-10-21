pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 45, unit: 'MINUTES')
  }

  parameters {
    string(name: 'COUNT',        defaultValue: '2',  description: 'Anzahl der Odoo-Instanzen')
    string(name: 'PREFIX',       defaultValue: 'demo', description: 'Präfix für Instanznamen (demo -> demo1, demo2 …)')
    string(name: 'DOMAIN_BASE',  defaultValue: '',   description: 'Traefik-Domain-Basis, z.B. 91-107-228-241.nip.io (leer = ohne Traefik)')
    string(name: 'PARALLEL',     defaultValue: '5',  description: 'Parallel gestartete Instanzen im Batch')
    string(name: 'CUSTOMER',     defaultValue: '',   description: 'Optionaler Kundenname/Label')
    booleanParam(name: 'RUN_QS',    defaultValue: true,  description: 'Qualitätssicherung/Smoke-Tests ausführen')
    booleanParam(name: 'TEARDOWN',  defaultValue: false, description: 'Instanzen nach Pipeline wieder entfernen')

    // NEU: QS-Template Checkout steuerbar inkl. Credentials
    string(name: 'QA_TEMPLATE_REPO',   defaultValue: 'https://github.com/ifegmbh/ife-addons-repo-template', description: 'Repo-URL des QS-Templates')
    string(name: 'QA_TEMPLATE_BRANCH', defaultValue: 'main', description: 'Branch des QS-Templates')
    string(name: 'QA_TEMPLATE_CRED',   defaultValue: '', description: 'Jenkins Credentials ID (PAT/SSH). Leer = ohne Credentials versuchen')
  }

  environment {
    RUN_TAG = "${env.JOB_NAME}-${env.BUILD_NUMBER}"
    LOGDIR  = "logs-${env.BUILD_NUMBER}"
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
          script {
            if (params.QA_TEMPLATE_CRED?.trim()) {
              git url: params.QA_TEMPLATE_REPO, branch: params.QA_TEMPLATE_BRANCH, credentialsId: params.QA_TEMPLATE_CRED
            } else {
              git url: params.QA_TEMPLATE_REPO, branch: params.QA_TEMPLATE_BRANCH
            }
          }
        }
      }
    }

    stage('Start Instances') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p "${LOGDIR}"
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
            for i in $(seq 1 "${COUNT}"); do
              NAME="${PREFIX}${i}"
              HOST="$(echo "${NAME}.${DOMAIN_BASE}" | tr '[:upper:]' '[:lower:]')"
              echo "[TEST] ${HOST} /web/login"
              if ! curl -fsS -m 5 --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" > /dev/null ; then
                echo "[ERROR] Smoke-Test fehlgeschlagen: ${HOST}"
                OK=0
              fi
            done
          else
            for i in $(seq 1 "${COUNT}"); do
              NAME="${PREFIX}${i}"
              NAME_LC="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
              NAME_LC="$(echo "${NAME_LC}" | sed 's/^[^a-z0-9]//')"
              OFFSET=$(echo -n "${NAME_LC}" | cksum | awk '{print $1 % 200}')
              PORT=$((8069 + OFFSET))
              echo "[TEST] ${NAME_LC} -> http://127.0.0.1:${PORT}/web/login"
              if ! curl -fsS -m 5 "http://127.0.0.1:${PORT}/web/login" > /dev/null ; then
                echo "[ERROR] Smoke-Test fehlgeschlagen: ${NAME_LC} Port=${PORT}"
                OK=0
              fi
            done
          fi

          if [[ -f qa-template/run_qs.sh ]]; then
            echo "[INFO] Starte qa-template/run_qs.sh …"
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
            docker compose -p "${NAME_LC}" logs --no-color > "${LOGDIR}/${NAME_LC}.log" 2>&1 || true
          done

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
