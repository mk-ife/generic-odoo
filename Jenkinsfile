pipeline {
  agent any

  options { timestamps() }

  parameters {
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Instanz-Präfix (z.B. "kunde-a")')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Basis-Domain für Traefik (nip.io / echte Domain)')
    string(name: 'COUNT', defaultValue: '1', description: 'Wie viele Instanzen starten')
    string(name: 'PARALLEL', defaultValue: '1', description: 'Wie viele parallel starten')

    booleanParam(name: 'ENABLE_TRAEFIK', defaultValue: true, description: 'Traefik/Reverse-Proxy verwenden (Host-Routing)')
    booleanParam(name: 'FORCE_HTTPS', defaultValue: true, description: 'HTTPS Router (Let’s Encrypt) aktivieren')
    string(name: 'LE_EMAIL', defaultValue: 'admin@example.com', description: 'E-Mail für Let’s Encrypt (ACME)')

    choice(name: 'AUTH_MODE', choices: ['none', 'usernamePassword', 'sshKey'], description: 'Zugriffsdaten-Quelle')
    credentials(name: 'AUTH_CREDENTIALS_ID', defaultValue: '', description: 'Jenkins-Credentials (Username/Password ODER SSH-Key)')

    booleanParam(name: 'INCLUDE_SECRETS_IN_DASHBOARD', defaultValue: false, description: '⚠️ Zugangsdaten im Dashboard mitspeichern (nicht im Log)')
  }

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    // generische Defaults, odoo-init/entry.sh setzt die DB etc. korrekt
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Sanity (compose render, Info)') {
      steps {
        sh '''
          set -euo pipefail
          docker compose -f docker-compose.yml ${FORCE_HTTPS == 'true' ? '-f docker-compose.https.yml' : ''} config | tee .compose.rendered.yaml
          sed -n '1,120p' .compose.rendered.yaml
          echo "INFO: HTTPS overlay: ${FORCE_HTTPS}"
        '''
      }
    }

    stage('Install docker compose cli (job-lokal)') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            echo "Install docker-compose v2.29.7"
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version
        '''
      }
    }

    stage('Start/ensure Traefik (optional, mit ACME)') {
      when { expression { return params.ENABLE_TRAEFIK } }
      steps {
        sh '''
          set -euo pipefail
          mkdir -p traefik
          [ -f traefik/acme.json ] || { touch traefik/acme.json; chmod 600 traefik/acme.json; }
          export LE_EMAIL="${LE_EMAIL}"
          docker compose -f docker-compose.traefik.yml up -d
          echo "Traefik up. Dashboard via container port 8080 (nur intern)."
        '''
      }
    }

    stage('Deploy batch') {
      environment {
        TRAEFIK_ENABLE = "${ENABLE_TRAEFIK ? 'true' : 'false'}"
      }
      steps {
        script {
          // Credentials nur laden, wenn gewählt
          if (params.AUTH_MODE == 'usernamePassword' && params.AUTH_CREDENTIALS_ID?.trim()) {
            withCredentials([usernamePassword(credentialsId: params.AUTH_CREDENTIALS_ID, usernameVariable: 'AUTH_USER', passwordVariable: 'AUTH_PASS')]) {
              sh """
                set -euo pipefail
                ./scripts/instances-batch.sh ${params.COUNT} '${params.PREFIX}' '${params.DOMAIN_BASE}' ${params.PARALLEL}
              """
              // Werte behalten wir NUR in Env für das Dashboard-File (nicht echo'n)
            }
          } else if (params.AUTH_MODE == 'sshKey' && params.AUTH_CREDENTIALS_ID?.trim()) {
            withCredentials([sshUserPrivateKey(credentialsId: params.AUTH_CREDENTIALS_ID, keyFileVariable: 'AUTH_SSH_KEY', usernameVariable: 'AUTH_SSH_USER')]) {
              sh """
                set -euo pipefail
                ./scripts/instances-batch.sh ${params.COUNT} '${params.PREFIX}' '${params.DOMAIN_BASE}' ${params.PARALLEL}
              """
            }
          } else {
            sh """
              set -euo pipefail
              ./scripts/instances-batch.sh ${params.COUNT} '${params.PREFIX}' '${params.DOMAIN_BASE}' ${params.PARALLEL}
            """
          }
        }
      }
    }

    stage('Smoke') {
      steps {
        sh '''
          set -euo pipefail
          for i in $(seq 1 ${COUNT}); do
            NAME="${PREFIX}${i}"
            HOST="${NAME}.${DOMAIN_BASE}"
            if [ "${ENABLE_TRAEFIK}" = "true" ]; then
              echo "Test: curl -sI --resolve '${HOST}:80:127.0.0.1' http://${HOST}/web/login | sed -n '1,5p'"
              curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,5p' || true
              if [ "${FORCE_HTTPS}" = "true" ]; then
                echo "Test(HTTPS): curl -skI --resolve '${HOST}:443:127.0.0.1' https://${HOST}/web/login | sed -n '1,5p'"
                curl -skI --resolve "${HOST}:443:127.0.0.1" "https://${HOST}/web/login" | sed -n '1,5p' || true
              fi
            else
              echo "Traefik disabled – überspringe Host-Test."
            fi
          done
        '''
      }
    }

    stage('Dashboard bauen (CSV/HTML)') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p build
          CSV="build/dashboard.csv"
          HTML="build/dashboard.html"

          echo "name,url,db_name,cred_mode,cred_id,username,password,ssh_user,ssh_key_hint" > "$CSV"

          for i in $(seq 1 ${COUNT}); do
            NAME="${PREFIX}${i}"
            HOST="${NAME}.${DOMAIN_BASE}"
            URL="http://${HOST}/web"
            [ "${FORCE_HTTPS}" = "true" ] && URL="https://${HOST}/web"
            DB="${NAME}_db"

            CRED_MODE="${AUTH_MODE}"
            CRED_ID="${AUTH_CREDENTIALS_ID}"

            U=""; P=""; SU=""; K=""

            if [ "${INCLUDE_SECRETS_IN_DASHBOARD}" = "true" ]; then
              if [ "${AUTH_MODE}" = "usernamePassword" ]; then
                U="${AUTH_USER-}"
                P="${AUTH_PASS-}"
              elif [ "${AUTH_MODE}" = "sshKey" ]; then
                SU="${AUTH_SSH_USER-}"
                K="(private key via Jenkins cred: ${AUTH_CREDENTIALS_ID})"
              fi
            fi

            echo "${NAME},${URL},${DB},${CRED_MODE},${CRED_ID},${U},${P},${SU},${K}" >> "$CSV"
          done

          # HTML aus CSV
          {
            echo "<html><head><meta charset=\\"utf-8\\"><title>Odoo Demo Dashboard</title>"
            echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px}</style>"
            echo "</head><body><h1>Odoo Demo Dashboard</h1>"
            echo "<table><tr><th>Name</th><th>URL</th><th>DB</th><th>Cred-Mode</th><th>Cred-ID</th><th>User</th><th>Password</th><th>SSH-User</th><th>SSH-Key</th></tr>"
            tail -n +2 "$CSV" | while IFS=, read -r n u d cm cid user pass su key; do
              echo "<tr><td>${n}</td><td><a href=\\"${u}\\">${u}</a></td><td>${d}</td><td>${cm}</td><td>${cid}</td><td>${user}</td><td>${pass}</td><td>${su}</td><td>${key}</td></tr>"
            done
            echo "</table></body></html>"
          } > "$HTML"
        '''
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
