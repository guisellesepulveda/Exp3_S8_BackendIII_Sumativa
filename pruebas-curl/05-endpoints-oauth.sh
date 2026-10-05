#!/usr/bin/env bash
# Metadatos OIDC, JWKS e introspeccion
source "$(dirname "$0")/00-env.sh"; requisitos
titulo "05 - Endpoints estandar del Authorization Server"

paso "Metadatos OIDC"
curl -s "$AUTH_URL/.well-known/openid-configuration" | jq '{issuer, token_endpoint, authorization_endpoint, jwks_uri, grant_types_supported}'

paso "JWKS (clave publica RSA con la que los servicios validan los tokens)"
curl -s "$AUTH_URL/oauth2/jwks" | jq '.keys[] | {kty, alg, use, kid}'

paso "Introspeccion de un token valido (esperado: active=true)"
R=$(token_reader)
curl -s -u banco-reader:reader-secret -d "token=$R" "$AUTH_URL/oauth2/introspect" | jq

paso "Introspeccion de un token basura (esperado: active=false)"
curl -s -u banco-reader:reader-secret -d "token=abc.def.ghi" "$AUTH_URL/oauth2/introspect" | jq
