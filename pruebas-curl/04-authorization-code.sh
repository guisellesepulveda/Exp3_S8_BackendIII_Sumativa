#!/usr/bin/env bash
# Flujo Authorization Code (usuario final). Dos modos:
#   ./04-authorization-code.sh            -> imprime la URL para abrir en el navegador
#   ./04-authorization-code.sh <CODE>     -> canjea el code y prueba el token
#   ./04-authorization-code.sh auto user user123   -> hace todo el flujo sin navegador (login + consentimiento)
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "04 - Authorization Code"
B=http://127.0.0.1:8081
REDIR=http://127.0.0.1:8081/authorized
URL="$B/oauth2/authorize?response_type=code&client_id=banco-web&scope=openid%20read%20write&redirect_uri=$REDIR&state=demo123"

canjear() {
  curl -s -u banco-web:web-secret -d grant_type=authorization_code -d "code=$1" -d "redirect_uri=$REDIR" "$AUTH_URL/oauth2/token" > /tmp/tokens-authcode.json
  paso "Campos de la respuesta"; jq 'keys' /tmp/tokens-authcode.json
  UT=$(jq -r .access_token /tmp/tokens-authcode.json)
  paso "Claims del access token"; jwt "$UT"
  paso "GET intereses con el token del usuario (esperado: 200)"
  codigo GET -H "Authorization: Bearer $UT" "$INT_URL/api/intereses?size=1"; echo
  paso "POST rerun con el token del usuario (200 si es admin, 403 si es user)"
  codigo POST -H "Authorization: Bearer $UT" "$INT_URL/api/migracion/rerun"; echo
  paso "/userinfo (OIDC)"; curl -s -H "Authorization: Bearer $UT" "$AUTH_URL/userinfo" | jq -c .
  paso "Refresh token -> nuevo access token"
  RT=$(jq -r .refresh_token /tmp/tokens-authcode.json)
  curl -s -u banco-web:web-secret -d grant_type=refresh_token -d "refresh_token=$RT" "$AUTH_URL/oauth2/token" | jq 'keys'
}

if [ "${1:-}" = "auto" ]; then
  U=${2:-user}; P=${3:-user123}; J=$(mktemp)
  curl -s -c "$J" -b "$J" -o /dev/null -L "$URL"
  CSRF=$(curl -s -c "$J" -b "$J" "$B/login" | grep -o 'name="_csrf" type="hidden" value="[^"]*"' | sed 's/.*value="//;s/"//')
  curl -s -c "$J" -b "$J" -o /dev/null -d "username=$U&password=$P&_csrf=$CSRF" "$B/login"
  STATE=$(curl -s -c "$J" -b "$J" "$URL" | grep -o 'name="state" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
  LOC=$(curl -s -c "$J" -b "$J" -o /dev/null -w '%{redirect_url}' \
        -d client_id=banco-web -d "state=$STATE" -d scope=openid -d scope=read -d scope=write "$B/oauth2/authorize")
  CODE=$(echo "$LOC" | sed 's/.*code=\([^&]*\).*/\1/')
  paso "Usuario '$U' autenticado; code obtenido: ${CODE:0:20}..."
  canjear "$CODE"
elif [ -n "${1:-}" ]; then
  canjear "$1"
else
  paso "1) Abre esta URL en el navegador, haz login (user/user123 o admin/admin123) y acepta el consentimiento:"
  echo "$URL"
  paso "2) Copia el 'code' que muestra /authorized y ejecuta:  ./04-authorization-code.sh <CODE>"
fi
