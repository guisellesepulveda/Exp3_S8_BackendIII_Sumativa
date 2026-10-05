#!/usr/bin/env bash
# Circuit Breaker + Retry + Fallback (Resilience4j) en la llamada Feign transacciones -> intereses
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "09 - Resilience4j: Circuit Breaker + Fallback"
READER=$(token_reader)
cd "$ROOT"
cb() { curl -s -H "Authorization: Bearer $READER" "$TX_URL/actuator/circuitbreakers" | jq -c '.circuitBreakers.interesesClient | {state, failureRate, failedCalls, notPermittedCalls}'; }
llamada() { curl -s -H "Authorization: Bearer $READER" "$TX_URL/api/transacciones/resumen-con-intereses/133" | jq -c .; }

paso "Llamada normal (esperado: fallback=false)"; llamada; cb

paso "Deteniendo intereses-service"
docker compose stop intereses-service >/dev/null 2>&1

paso "6 llamadas con el servicio caido (esperado: fallback=true, sin errores 500)"
for i in 1 2 3 4 5 6; do llamada; done
paso "Estado del circuito (esperado: OPEN)"; cb

paso "Levantando intereses-service y esperando recuperacion (~60 s)"
docker compose start intereses-service >/dev/null 2>&1
for _ in $(seq 1 40); do
  sleep 3
  R=$(curl -s -H "Authorization: Bearer $READER" "$TX_URL/api/transacciones/resumen-con-intereses/133" | jq -r .fallback)
  [ "$R" = "false" ] && break
done
llamada; cb
