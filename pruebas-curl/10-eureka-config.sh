#!/usr/bin/env bash
# Service Discovery, Config Server y health de todos los servicios
source "$(dirname "$0")/00-env.sh"
titulo "10 - Eureka, Config Server y health"

paso "Servicios registrados en Eureka"
curl -s "$EUREKA_URL/eureka/apps" -H 'Accept: application/json' \
  | jq -r '.applications.application[] | "\(.name)\t\(.instance[0].status)"' | column -t

paso "Config Server: fuentes servidas a transacciones-service (perfil docker)"
curl -s "$CONFIG_URL/transacciones-service/docker" | jq -c '[.propertySources[].name]'

paso "Health de cada componente"
for p in 8888 8761 8081 8082 8083 8084; do
  printf '%s -> ' "$p"; curl -s "http://localhost:$p/actuator/health" | jq -r .status
done
