pipeline {
  agent any
  options {
    timestamps()
  }

  parameters {
    string(name: 'COUNT',       defaultValue: '1',                    description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX',      defaultValue: 'demo',                 description: 'Präfix für Instanznamen (z.B. demo, kunde-a)')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io',description: 'Traefik Domain (leer = ohne Traefik)')
    string(name: 'PARALLEL',    defaultValue: '1',                    description: 'Parallelität beim Batch-Start')
  }

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    COMPOSE_VER  = "v2.29.7"
    COMPOSE_URL  = "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Setup docker compose CLI') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"

          if docker compose version >/dev/null 2>&1; then
            docker compose version
          else
            if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
              echo "Lade docker compose ${COMPOSE_VER}…"
              # curl oder wget, je nachdem was vorhanden ist
              if command -v curl >/dev/null 2>&1; then
                curl -fsSL "${COMPOSE_URL}" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
              else
                wget -qO "$DOCKER_CONFIG/cli-plugins/docker-compose" "${COMPOSE_URL}"
              fi
              chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
            fi
            docker compose version
          fi
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          cd "$WORKSPACE"
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }

    stage('Smoke (kurz)') {
      when { expression { return params.DOMAIN_BASE?.trim() } }
      steps {
        sh '''
          set -eux
          for i in $(seq 1 "${COUNT}"); do
            host="${PREFIX}${i}.${DOMAIN_BASE}"
            echo "Test $i: ${host}"
            curl -sI --resolve "${host}:80:127.0.0.1" "http://${host}/web/login" | sed -n '1,5p'
          done
        '''
      }
    }
  }

  post {
    success { echo "✅ Batch erfolgreich deployt." }
    failure { echo "❌ Fehler beim Deploy – Logs prüfen." }
  }
}
