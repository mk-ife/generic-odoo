pipeline {
  agent any
  options { timestamps() }
  parameters {
    string(name: 'COUNT', defaultValue: '1', description: 'Wie viele Instanzen?')
    string(name: 'PREFIX', defaultValue: 'demo', description: 'Namenspräfix, z.B. demo')
    string(name: 'DOMAIN_BASE', defaultValue: '91-107-228-241.nip.io', description: 'Traefik Domain-Basis')
    string(name: 'PARALLEL', defaultValue: '1', description: 'Wie viele parallel starten')
  }
  environment {
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Compute prefix') {
      steps {
        script {
          env.PREFIX_EFF = params.PREFIX?.trim()
          if (!env.PREFIX_EFF) { error "PREFIX leer" }
          echo "Using PREFIX: ${env.PREFIX_EFF}"
        }
      }
    }

    stage('Install docker compose (userland)') {
      steps {
        sh '''
          set -eux
          mkdir -p "$DOCKER_CONFIG/cli-plugins"
          if [ ! -x "$DOCKER_CONFIG/cli-plugins/docker-compose" ]; then
            curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
            chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
          fi
          docker compose version
        '''
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          cd "$WORKSPACE"
          ./scripts/instances-batch.sh "${COUNT}" "${PREFIX_EFF}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }

    stage('Smoke (kurz)') {
      when { expression { return params.COUNT?.toInteger() > 0 } }
      steps {
        sh '''
          set -eux
          FIRST="${PREFIX_EFF}1.${DOMAIN_BASE}"
          echo "Check ${FIRST} via Traefik"
          curl -sI --resolve "${FIRST}:80:127.0.0.1" "http://${FIRST}/web/login" | sed -n '1,5p'
        '''
      }
    }
  }
}
