#!/usr/bin/env bash
# Variables y funciones comunes. Los demas scripts hacen `source 00-env.sh`.
# Requiere: curl, jq, python3 (y docker compose para los scripts que detienen servicios).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_URL=${AUTH_URL:-http://localhost:8081}
TX_URL=${TX_URL:-http://localhost:8082}
INT_URL=${INT_URL:-http://localhost:8083}
CTA_URL=${CTA_URL:-http://localhost:8084}
EUREKA_URL=${EUREKA_URL:-http://localhost:8761}
CONFIG_URL=${CONFIG_URL:-http://localhost:8888}

titulo() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
paso()   { printf '\n\033[1;33m>> %s\033[0m\n' "$*"; }

# codigo HTTP de una peticion: codigo METODO URL [args curl...]
codigo() { curl -s -o /dev/null -w '%{http_code}' -X "$@"; }

# token_cc <client_id> <secret> "<scopes>"  -> access_token (client_credentials)
token_cc() {
  curl -s -u "$1:$2" -d grant_type=client_credentials -d "scope=$3" "$AUTH_URL/oauth2/token" | jq -r .access_token
}
token_admin()  { token_cc banco-admin  admin-secret  "read write"; }
token_reader() { token_cc banco-reader reader-secret "read"; }

# jwt <token> -> payload decodificado (base64url) como JSON
jwt() {
  python3 -c "import sys,base64,json;p=sys.argv[1].split('.')[1];print(json.dumps(json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4))),indent=2))" "$1"
}

# crear_tx <token> <cuentaId> <monto> <tipo> -> JSON de la transaccion creada
crear_tx() {
  curl -s -X POST -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d "{\"cuentaId\":$2,\"monto\":$3,\"tipo\":\"$4\"}" "$TX_URL/api/transacciones"
}

# estado_tx <token> <id> -> estado actual
estado_tx() { curl -s -H "Authorization: Bearer $1" "$TX_URL/api/transacciones/$2" | jq -r .estado; }

# esperar_estado <token> <id> <estado_esperado> [segundos]  (imprime el estado final)
esperar_estado() {
  local t=$1 id=$2 esperado=$3 max=${4:-60} e=""
  for _ in $(seq 1 "$max"); do
    e=$(estado_tx "$t" "$id")
    [ "$e" = "$esperado" ] && break
    sleep 1
  done
  echo "$e"
}

requisitos() {
  for c in curl jq python3; do command -v "$c" >/dev/null || { echo "Falta '$c'"; exit 1; }; done
  curl -s -o /dev/null "$AUTH_URL/actuator/health" || { echo "auth-service no responde en $AUTH_URL. ¿docker compose up -d?"; exit 1; }
}
