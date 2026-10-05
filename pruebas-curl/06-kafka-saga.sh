#!/usr/bin/env bash
# Saga coreografiada sobre Kafka: transaccion.registrada -> cuenta.movimiento-aplicado -> interes.recalculado
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "06 - Saga Kafka (flujo feliz)"
ADMIN=$(token_admin)

paso "POST /api/transacciones (responde 202 con estado PENDIENTE)"
R=$(crear_tx "$ADMIN" 137 500 credito); echo "$R" | jq -c .
ID=$(echo "$R" | jq -r .id)

paso "Esperando que la saga complete (esperado: CONFIRMADA)"
echo "estado final: $(esperar_estado "$ADMIN" "$ID" CONFIRMADA 30)"

paso "Transaccion final"
curl -s -H "Authorization: Bearer $ADMIN" "$TX_URL/api/transacciones/$ID" | jq -c .

paso "Logs de los consumidores (docker compose)"
(cd "$ROOT" && docker compose logs --tail=3 cuentas-service intereses-service 2>/dev/null | grep -E "Movimiento|Saldo" )
echo; echo "Kafka UI: http://localhost:8090 -> Topics"
