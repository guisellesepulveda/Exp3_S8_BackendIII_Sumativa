#!/usr/bin/env bash
# OAuth2 client_credentials: respuesta del endpoint de token y claims decodificados
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "02 - Obtener tokens (client_credentials)"

paso "Respuesta de /oauth2/token para banco-admin (scopes read write)"
curl -s -u banco-admin:admin-secret -d grant_type=client_credentials -d "scope=read write" "$AUTH_URL/oauth2/token" \
  | jq '.access_token |= (.[0:40] + "...")'

paso "Claims del token de banco-admin (esperado: scope read+write, roles ADMIN+USER)"
jwt "$(token_admin)"

paso "Claims del token de banco-reader (esperado: scope read, roles USER)"
jwt "$(token_reader)"

paso "Credenciales de cliente incorrectas (esperado: 401 invalid_client)"
curl -s -i -u banco-admin:mala -d grant_type=client_credentials "$AUTH_URL/oauth2/token" | sed -n '1p;$p'

paso "Scope no permitido para banco-reader pidiendo 'write' (esperado: invalid_scope)"
curl -s -u banco-reader:reader-secret -d grant_type=client_credentials -d scope=write "$AUTH_URL/oauth2/token" | jq
