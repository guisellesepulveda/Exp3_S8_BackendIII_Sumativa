#!/usr/bin/env bash
# Kafka caido: el publicador (Resilience4j) cae al fallback y la transaccion queda PENDIENTE_PUBLICACION.
# Al volver el broker, el scheduler (outbox) la republica. Usa `docker compose stop/start kafka`.
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "07 - Kafka caido -> PENDIENTE_PUBLICACION -> recuperacion"
ADMIN=$(token_admin)
cd "$ROOT"

paso "Deteniendo Kafka"
docker compose stop kafka >/dev/null 2>&1

paso "POST con Kafka caido (esperado: estado PENDIENTE_PUBLICACION, la API sigue respondiendo)"
R=$(crear_tx "$ADMIN" 137 100 credito); echo "$R" | jq -c .
ID=$(echo "$R" | jq -r .id)

paso "Circuit breaker kafkaPublisher"
curl -s -H "Authorization: Bearer $ADMIN" "$TX_URL/actuator/circuitbreakers" | jq -c '.circuitBreakers.kafkaPublisher | {state, failureRate, bufferedCalls, failedCalls}'

paso "Levantando Kafka de nuevo"
docker compose start kafka >/dev/null 2>&1
echo "Esperando republicacion (hasta 120 s)..."
echo "estado final: $(esperar_estado "$ADMIN" "$ID" CONFIRMADA 120)  (esperado: CONFIRMADA)"
