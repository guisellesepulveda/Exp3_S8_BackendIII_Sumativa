#!/usr/bin/env bash
# Ejecuta todas las pruebas no interactivas en orden.
#   ./run-all.sh            -> pruebas que no detienen servicios
#   ./run-all.sh --caidas   -> incluye 07 (Kafka caido) y 09 (circuit breaker, detiene intereses-service)
D="$(cd "$(dirname "$0")" && pwd)"
for s in 10-eureka-config 01-sin-token 02-obtener-tokens 03-autorizacion-scopes-roles 05-endpoints-oauth 06-kafka-saga 08-fallo-negocio-dlt; do
  bash "$D/$s.sh"
done
bash "$D/04-authorization-code.sh" auto user user123
if [ "${1:-}" = "--caidas" ]; then
  bash "$D/07-kafka-caido.sh"
  bash "$D/09-resilience-circuit-breaker.sh"
fi
