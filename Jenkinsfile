pipeline {
  agent any
  options { timestamps() }

  parameters {
    string(name: 'COUNT', defaultValue: '1', description: 'Wie viele Instanzen starten')
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Präfix für Instanznamen (z.B. demo, kunde-a, ...)')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Traefik Domain-Basis (leer = ohne Traefik)')
    string(name: 'PARALLEL', defaultValue: '1', description: 'Wieviele parallel starten (1..N)')
  }

  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          git rev-parse --short HEAD
          # Sichtprüfung, ob scripts vorhanden
          ls -la scripts || true
        '''
      }
    }

    stage('Preflight: ensure docker compose CLI') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            echo "Install docker compose v2.29.7 into workspace CLI plugins..."
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
              -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version
        '''
      }
    }

    stage('Guard: odoo-init.sh muss Datei sein (kein Ordner)') {
      steps {
        sh '''
          set -eux
          cd "$WORKSPACE"

          # Wenn durch einen früheren fehlerhaften Run ein VERZEICHNIS angelegt wurde, löschen
          if [ -d scripts/odoo-init.sh ]; then
            echo "Found directory scripts/odoo-init.sh — removing and restoring from git"
            rm -rf scripts/odoo-init.sh
            git checkout -- scripts/odoo-init.sh || true
          fi

          # Wenn die Datei fehlt, abbrechen mit klarer Meldung
          if [ ! -f scripts/odoo-init.sh ]; then
            echo "ERROR: scripts/odoo-init.sh fehlt im Workspace!"
            echo "Bitte sicherstellen, dass die Datei im Repo liegt."
            exit 1
          fi

          # Info & ausführbar machen
          ls -l scripts/odoo-init.sh
          sed -n '1,60p' scripts/odoo-init.sh || true
          chmod +x scripts/odoo-init.sh
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          cd "$WORKSPACE"
          # Starten
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }

    stage('Smoke (kurz)') {
      when { expression { return params.COUNT?.trim() != '0' } }
      steps {
        sh '''
          set -eux
          FIRST="${PREFIX}1"
          HOST="${FIRST}.${DOMAIN_BASE}"
          echo "Smoke-Test gegen http://${HOST}/web/login"
          curl -sI --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/web/login" | sed -n '1,5p'
        '''
      }
    }
  }
}
