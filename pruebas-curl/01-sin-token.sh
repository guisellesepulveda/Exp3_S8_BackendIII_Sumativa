#!/usr/bin/env bash
# Peticiones sin token o con token invalido -> 401
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "01 - Sin token / token invalido (esperado: 401)"

paso "GET sin token"
curl -i -s "$TX_URL/api/transacciones" | head -5

paso "GET con token manipulado"
curl -i -s -H "Authorization: Bearer abc.def.ghi" "$TX_URL/api/transacciones" | head -5

paso "Health publico (esperado: 200)"
codigo GET "$TX_URL/actuator/health"; echo
