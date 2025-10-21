pipeline {
  agent any
  options { timestamps() }

  parameters {
    string(name: 'COUNT',        defaultValue: '5',  description: 'Wie viele Instanzen starten (instances-batch.sh <COUNT>)')
    string(name: 'PREFIX',       defaultValue: 'demo', description: 'Namenspräfix (demo1, demo2, …). Kann pro Lauf eindeutig gemacht werden.')
    string(name: 'DOMAIN_BASE',  defaultValue: '91-107-228-241.nip.io', description: 'Leer = ohne Traefik; sonst Domain (Traefik nötig)')
    string(name: 'PARALLEL',     defaultValue: '5',  description: 'Wie viele Instanzen parallel starten')
    booleanParam(name: 'ADD_BUILDNUM_TO_PREFIX', defaultValue: true, description: 'Präfix um BUILD_NUMBER erweitern (vermeidet Kollisionen)')
  }

  stages {
    stage('Checkout generic-odoo') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Compute prefix') {
      steps {
        script {
          if (params.ADD_BUILDNUM_TO_PREFIX) {
            // ergibt z.B. "demo21-" -> Instanzen demo21-1, demo21-2, …
            env.EFFECTIVE_PREFIX = "${params.PREFIX}${env.BUILD_NUMBER}-"
          } else {
            env.EFFECTIVE_PREFIX = params.PREFIX
          }
          echo "Using PREFIX: ${env.EFFECTIVE_PREFIX}"
        }
      }
    }

    stage('Deploy batch') {
      steps {
        sh '''
          set -eux
          cd "${WORKSPACE}"
          # Batch-Start (Traefik aktiv, wenn DOMAIN_BASE nicht leer ist)
          ./scripts/instances-batch.sh "${COUNT}" "${EFFECTIVE_PREFIX}" "${DOMAIN_BASE}" "${PARALLEL}"
        '''
      }
    }

    stage('Smoke Tests') {
      steps {
        sh '''
          set -eux
          cd "${WORKSPACE}"

          # kleine Helfer:
          curl_head_ok() {
            url="$1"
            hosthdr="$2"   # leer = ohne Host-Override
            if [ -n "$hosthdr" ]; then
              code=$(curl -sI --max-time 5 --resolve "$hosthdr" "$url" -o /dev/null -w '%{http_code}')
            else
              code=$(curl -sI --max-time 5 "$url" -o /dev/null -w '%{http_code}')
            fi
            [ "$code" = "200" ]
          }

          for n in $(seq 1 ${COUNT}); do
            proj="${EFFECTIVE_PREFIX}${n}"
            odoo_ct="${proj}-odoo-1"
            db_ct="${proj}-db-1"

            echo "== Smoke for project: ${proj}"

            # 1) Container-Health (odoo)
            health=$(docker inspect -f '{{.State.Health.Status}}' "${odoo_ct}")
            echo "   odoo health: ${health}"
            test "${health}" = "healthy"

            # 2) Volumes exist & sind eindeutig
            docker volume inspect "odoo_${proj}_data" >/dev/null
            docker volume inspect "pg_${proj}_data" >/dev/null

            # 3) HTTP erreichbar
            if [ -n "${DOMAIN_BASE}" ]; then
              host="${proj}.${DOMAIN_BASE}"
              echo "   test via Traefik: http://${host}/web/login"
              curl_head_ok "http://${host}/web/login" "${host}:80:127.0.0.1"
            else
              # ohne Traefik: Port wurde in instance-up berechnet; wir lesen ihn aus dem Container-Netz (published Ports)
              # Falls kein Publish existiert, testen intern via Container-IP.
              port=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "8069/tcp") 0).HostPort}}' "${odoo_ct}" 2>/dev/null || true)
              if [ -n "${port}" ] && [ "${port}" != "<no value>" ]; then
                echo "   test via localhost:${port}"
                curl_head_ok "http://127.0.0.1:${port}/web/login" ""
              else
                ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${odoo_ct}")
                echo "   test via container ip ${ip}:8069"
                code=$(docker exec "${odoo_ct}" sh -lc "curl -sI http://127.0.0.1:8069/web/login -o /dev/null -w '%{http_code}'")
                [ "$code" = "200" ]
              fi
            fi

            # 4) DB-Container läuft
            db_state=$(docker inspect -f '{{.State.Status}}' "${db_ct}")
            echo "   db state: ${db_state}"
            test "${db_state}" = "running"
          done

          echo "Smoke OK for ${COUNT} instance(s)."
        '''
      }
    }

    stage('Rollback-Isolation Test') {
      steps {
        sh '''
          set -eux
          cd "${WORKSPACE}"

          # Wir stoppen 1 Instanz und prüfen, dass die anderen weiterhin OK sind
          first_proj="${EFFECTIVE_PREFIX}1"
          echo "Stopping 1 instance for rollback test: ${first_proj}"
          docker compose -p "${first_proj}" stop odoo

          # Prüfe alle anderen (2..COUNT)
          if [ "${COUNT}" -ge 2 ]; then
            for n in $(seq 2 ${COUNT}); do
              proj="${EFFECTIVE_PREFIX}${n}"
              odoo_ct="${proj}-odoo-1"

              # health
              health=$(docker inspect -f '{{.State.Health.Status}}' "${odoo_ct}")
              echo "   ${proj} health: ${health}"
              test "${health}" = "healthy"

              # HTTP
              if [ -n "${DOMAIN_BASE}" ]; then
                host="${proj}.${DOMAIN_BASE}"
                code=$(curl -sI --max-time 5 --resolve "${host}:80:127.0.0.1" "http://${host}/web/login" -o /dev/null -w '%{http_code}')
                [ "$code" = "200" ]
              else
                port=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "8069/tcp") 0).HostPort}}' "${odoo_ct}" 2>/dev/null || true)
                if [ -n "${port}" ] && [ "${port}" != "<no value>" ]; then
                  code=$(curl -sI --max-time 5 "http://127.0.0.1:${port}/web/login" -o /dev/null -w '%{http_code}')
                  [ "$code" = "200" ]
                else
                  code=$(docker exec "${odoo_ct}" sh -lc "curl -sI http://127.0.0.1:8069/web/login -o /dev/null -w '%{http_code}'")
                  [ "$code" = "200" ]
                fi
              fi
            done
          fi

          # Starten wir die 1. Instanz wieder (sauberer Abschluss)
          docker compose -p "${first_proj}" start odoo || true
          echo "Rollback/Isolation OK."
        '''
      }
    }

    stage('Hints / URLs') {
      steps {
        sh '''
          set -eu
          if [ -n "${DOMAIN_BASE}" ]; then
            for n in $(seq 1 ${COUNT}); do
              host="${EFFECTIVE_PREFIX}${n}.${DOMAIN_BASE}"
              echo "Open:   http://${host}/web"
              echo "Test:   curl -sI --resolve '${host}:80:127.0.0.1' http://${host}/web/login | sed -n '1,5p'"
              echo "Note:   Request via Traefik (:80) – deshalb '--resolve …:80:127.0.0.1'."
              echo
            done
          else
            echo "Ohne Traefik: Ports werden automatisch berechnet; siehe 'docker ps' -> HostPort für 8069/tcp."
          fi
        '''
      }
    }
  }

  post {
    always {
      echo "Build ${env.BUILD_NUMBER} finished (result: ${currentBuild.currentResult})"
    }
  }
}
