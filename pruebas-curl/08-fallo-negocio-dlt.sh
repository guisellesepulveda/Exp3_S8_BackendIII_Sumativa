#!/usr/bin/env bash
# Cuenta inexistente en intereses -> reintentos con backoff -> DLT -> transaccion.fallida -> RECHAZADA + reverso
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "08 - Fallo de negocio: reintentos, Dead Letter Topic y compensacion"
ADMIN=$(token_admin)

paso "POST con cuentaId inexistente (99999)"
R=$(crear_tx "$ADMIN" 99999 100 debito); echo "$R" | jq -c .
ID=$(echo "$R" | jq -r .id)

paso "Esperando compensacion (esperado: RECHAZADA)"
echo "estado final: $(esperar_estado "$ADMIN" "$ID" RECHAZADA 60)"

paso "Logs de reintentos agotados y reverso"
(cd "$ROOT" && docker compose logs intereses-service cuentas-service 2>/dev/null | grep -E "Reintentos agotados|Reverso aplicado" | tail -4)
echo; echo "Kafka UI: http://localhost:8090 -> Topics -> cuenta.movimiento-aplicado.DLT y transaccion.fallida"
