# Pruebas con curl

Scripts para ejecutar y capturar cada prueba (ver [../docs/guia-evidencias.md](../docs/guia-evidencias.md) para el detalle de qué captura tomar).

Requisitos: sistema levantado (`docker compose up -d --build` desde la raíz y esperar a `healthy`), `curl`, `jq` y `python3`.

| Script | Qué prueba | Esperado |
|---|---|---|
| `10-eureka-config.sh` | Eureka, Config Server, health | 4 servicios `UP`, todos `UP` |
| `01-sin-token.sh` | Sin token / token falso | 401 |
| `02-obtener-tokens.sh` | `client_credentials` y claims | scopes y roles por cliente |
| `03-autorizacion-scopes-roles.sh` | Scopes `read`/`write` y rol `ADMIN` | 200 / 403 |
| `04-authorization-code.sh` | Authorization Code (navegador o `auto`) | login + consent + token |
| `05-endpoints-oauth.sh` | OIDC, JWKS, introspección | `active:true/false` |
| `06-kafka-saga.sh` | Saga Kafka feliz | `CONFIRMADA` |
| `07-kafka-caido.sh` | Kafka caído (detiene/levanta kafka) | `PENDIENTE_PUBLICACION` → `CONFIRMADA` |
| `08-fallo-negocio-dlt.sh` | Reintentos + DLT + compensación | `RECHAZADA` |
| `09-resilience-circuit-breaker.sh` | Circuit Breaker + fallback (detiene intereses) | `fallback:true`, `OPEN` → `CLOSED` |
| `run-all.sh [--caidas]` | Todo en orden | — |

```bash
cd pruebas-curl
./run-all.sh              # sin detener servicios
./04-authorization-code.sh            # modo navegador: imprime la URL
./04-authorization-code.sh auto admin admin123   # flujo completo sin navegador, como admin
```

Las URLs se pueden sobrescribir con variables de entorno (`TX_URL`, `AUTH_URL`, ...).
