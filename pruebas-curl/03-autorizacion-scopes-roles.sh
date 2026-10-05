#!/usr/bin/env bash
# Autorizacion por scope (read/write) y por rol (ADMIN) en los resource servers
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "03 - Autorizacion por scopes y roles"
ADMIN=$(token_admin); READER=$(token_reader)

paso "GET /api/transacciones con reader (esperado: 200)"
codigo GET -H "Authorization: Bearer $READER" "$TX_URL/api/transacciones?size=1"; echo
paso "GET en los otros dos servicios con reader (esperado: 200 200)"
codigo GET -H "Authorization: Bearer $READER" "$INT_URL/api/intereses?size=1"; echo
codigo GET -H "Authorization: Bearer $READER" "$CTA_URL/api/cuentas?size=1"; echo

paso "POST /api/transacciones con reader, sin scope write (esperado: 403)"
codigo POST -H "Authorization: Bearer $READER" -H 'Content-Type: application/json' \
  -d '{"cuentaId":137,"monto":10,"tipo":"credito"}' "$TX_URL/api/transacciones"; echo

paso "POST /api/migracion/rerun con reader, sin rol ADMIN (esperado: 403)"
codigo POST -H "Authorization: Bearer $READER" "$TX_URL/api/migracion/rerun"; echo

paso "POST /api/migracion/rerun con admin (esperado: 200)"
curl -s -X POST -H "Authorization: Bearer $ADMIN" "$TX_URL/api/migracion/rerun" | jq -c .

paso "Estado de la migracion en los 3 servicios (leidos/escritos/omitidos)"
for u in "$TX_URL" "$INT_URL" "$CTA_URL"; do
  curl -s -H "Authorization: Bearer $READER" "$u/api/migracion/status" | jq -c .
done
