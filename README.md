# Banco XYZ — Migración de Datos Legacy y Microservicios con Spring Cloud

Proyecto de migración y modernización de procesos batch de un banco ficticio (Banco XYZ). Parte de una arquitectura de microservicios con Spring Cloud que migra los datos legacy (CSV con errores típicos de un sistema batch antiguo) hacia bases de datos propias de cada servicio, y los expone mediante APIs REST protegidas con **OAuth 2.0** (Authorization Server propio + Resource Servers), con Service Discovery, Config Server centralizado, tolerancia a fallos (Resilience4j), mensajería asíncrona (Kafka) y despliegue completo con **Docker Compose**.

## Arquitectura

```
config-server (8888)        discovery-server / Eureka (8761)
        │                            │
        └──────────────┬─────────────┘
                        │  (config + registro)
        ┌───────────────┼────────────────┬─────────────────┐
        │               │                │                 │
  auth-service     transacciones-   intereses-service  cuentas-service
     (8081)        service (8082)      (8083)             (8084)
                        │                │                 │
                        └──► intereses ──┘                 │
                                         └──► cuentas ──────┘
                                                             │
                        cuentas ──► transacciones ◄─────────┘
```

- **config-server**: Spring Cloud Config Server (perfil `native`), sirve la configuración de todos los clientes desde `config-server/src/main/resources/config-repo/`.
- **discovery-server**: servidor Eureka standalone para Service Discovery.
- **auth-service**: **Authorization Server OAuth 2.0 / OpenID Connect** (Spring Authorization Server). Emite access tokens JWT firmados con RS256 y publica la clave pública en `/oauth2/jwks`. Grants: `client_credentials` y `authorization_code` + `refresh_token`.
- **transacciones-service**, **intereses-service**, **cuentas-service**: cada uno migra su CSV correspondiente con Spring Batch, expone una API REST protegida como **Resource Server OAuth2**, y llama a otro servicio vía Feign con Resilience4j (Circuit Breaker + Retry + fallback), formando un triángulo de dependencias:
  - `transacciones-service` → `intereses-service`
  - `intereses-service` → `cuentas-service`
  - `cuentas-service` → `transacciones-service`

### Módulos Maven

| Módulo | Puerto | Rol |
|---|---|---|
| `common-lib` | — | DTOs, eventos Kafka y converter de scopes/roles del token (no es una app Spring Boot) |
| `config-server` | 8888 | Config Server centralizado |
| `discovery-server` | 8761 | Eureka |
| `auth-service` | 8081 | Authorization Server OAuth2 / OIDC |
| `transacciones-service` | 8082 | Migración + API de `transacciones.csv` |
| `intereses-service` | 8083 | Migración + API de `intereses.csv` |
| `cuentas-service` | 8084 | Migración + API de `cuentas_anuales.csv` |

### Datos de origen

Cada microservicio de negocio migra su CSV desde `data/semana_3/` (copiado a `src/main/resources/data/` de cada módulo para no depender de rutas externas) hacia una base H2 en memoria propia (patrón *database per service*), usando un job de Spring Batch con políticas de skip para los problemas típicos de datos legacy:

1. **`transacciones.csv`**: fechas en 4 formatos (`yyyy-MM-dd`, `yyyy/MM/dd`, `dd-MM-yyyy`, `dd/MM/yyyy`), montos vacíos/negativos/cero, `tipo` inválido (`invalid`, `desconocido`).
2. **`intereses.csv`**: saldos vacíos/≤0, edades fuera de rango (1–100), `tipo` inválido (`-1`, `unknown`), filas duplicadas.
3. **`cuentas_anuales.csv`**: mismas 4 variantes de fecha, montos vacíos/negativos, `transaccion` con variante acentuada (`depósito` se normaliza, no se descarta; `pago` es inválido), `descripcion` vacía se reemplaza por `"Sin descripción"` en vez de descartar la fila.

Las filas inválidas se omiten (skip) vía Spring Batch (`faultTolerant().skip(...)`) y quedan registradas en el log y en el contador de migración de cada servicio (`GET /api/migracion/status`).

## Arquitectura de eventos (Kafka)

Las escrituras entre servicios usan una **saga coreografiada sobre Kafka**: `POST /api/transacciones` (transacciones-service) → `transaccion.registrada` → cuentas-service → `cuenta.movimiento-aplicado` → intereses-service → `interes.recalculado` → transacción `CONFIRMADA`. Los fallos usan reintentos, Dead Letter Topics y compensación (`transaccion.fallida`). Diagrama, tópicos y pruebas en [docs/arquitectura-eventos.md](docs/arquitectura-eventos.md). Kafka se levanta con `docker compose` (ver arriba).

## Requisitos

- **Opción Docker (recomendada)**: Docker Desktop / Docker Engine con Compose v2. No requiere Java ni Maven.
- **Opción local**: Java 17 y Maven 3.9+.
- Puertos libres: 8761, 8888, 8081, 8082, 8083, 8084, 9092, 8090

## Cómo levantar el proyecto

### Opción A — Docker Compose (todo el sistema con un comando)

```bash
docker compose up -d --build     # construye las 6 imágenes y levanta Kafka + 6 servicios en orden
docker compose ps                # todos deben quedar (healthy), ~1-2 min
docker compose down -v           # detener y limpiar
```

[docker-compose.yaml](docker-compose.yaml) orquesta: `kafka` (KRaft), `kafka-ui`, `config-server`, `discovery-server`, `auth-service`, `transacciones-service`, `intereses-service` y `cuentas-service`. Cada microservicio tiene su `Dockerfile` multi-etapa (`<servicio>/Dockerfile`: build con Maven + runtime con JRE 17 y usuario sin privilegios). El orden de arranque se controla con `depends_on` + `healthcheck` (Kafka/Config/Eureka → auth-service → servicios de negocio). Dentro de Docker los servicios usan el perfil `docker` (`config-repo/application-docker.yml`), que reemplaza `localhost` por los nombres de servicio de la red.

### Opción B — Local con `java -jar`

```bash
mvn clean package -DskipTests
docker compose up -d kafka kafka-ui          # solo el broker Kafka

java -jar discovery-server/target/discovery-server-1.0.0.jar     # terminal 1
java -jar config-server/target/config-server-1.0.0.jar           # terminal 2
# esperar UP en :8761 y :8888, luego en cualquier orden:
java -jar auth-service/target/auth-service-1.0.0.jar
java -jar transacciones-service/target/transacciones-service-1.0.0.jar
java -jar intereses-service/target/intereses-service-1.0.0.jar
java -jar cuentas-service/target/cuentas-service-1.0.0.jar
```

Cada servicio ejecuta su migración de datos automáticamente al arrancar (job de Spring Batch).

## Verificación

### Config Server centralizado

```bash
curl http://localhost:8888/transacciones-service/default
```

Debe devolver la configuración combinada (puerto, datasource, Eureka, Resilience4j, etc.).

### Service Discovery

Abrir `http://localhost:8761` en el navegador: deben listarse `AUTH-SERVICE`, `TRANSACCIONES-SERVICE`, `INTERESES-SERVICE` y `CUENTAS-SERVICE`, todos `UP`.

### Seguridad OAuth 2.0

Clientes registrados en `auth-service` (secretos de **demostración**, configurables por variables de entorno):

| client_id | secret | Grant | Scopes | Roles en el token |
|---|---|---|---|---|
| `banco-admin` | `admin-secret` | `client_credentials` | `read`, `write` | `ADMIN`, `USER` |
| `banco-reader` | `reader-secret` | `client_credentials` | `read` | `USER` |
| `banco-web` | `web-secret` | `authorization_code`, `refresh_token` | `openid`, `read`, `write` | los del usuario que se loguea |

Usuarios (solo para `authorization_code`): `admin` / `admin123` (`ADMIN`,`USER`) y `user` / `user123` (`USER`).

Reglas de autorización en los resource servers: `GET /api/**` exige scope `read`; `POST /api/**` exige scope `write`; `POST /api/migracion/rerun` exige rol `ADMIN`; `/actuator/health` es público.

```bash
# Token (client_credentials)
TOKEN=$(curl -s -u banco-admin:admin-secret -d grant_type=client_credentials -d "scope=read write" \
  http://localhost:8081/oauth2/token | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

curl -H "Authorization: Bearer $TOKEN" "http://localhost:8082/api/transacciones?size=2"   # 200
curl -i http://localhost:8082/api/transacciones                                            # 401 sin token
```

El flujo `authorization_code` (login + consentimiento en navegador) y el resto de pruebas paso a paso están en [docs/guia-evidencias.md](docs/guia-evidencias.md). Los curl listos para ejecutar están en [pruebas-curl/](pruebas-curl/README.md).

### Estado de la migración

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/api/migracion/status
curl -H "Authorization: Bearer $TOKEN" http://localhost:8083/api/migracion/status
curl -H "Authorization: Bearer $TOKEN" http://localhost:8084/api/migracion/status
```

Devuelve `{"leidos":N,"escritos":N,"omitidos":N}` por servicio.

### Tolerancia a fallos (Circuit Breaker + Retry + Fallback)

Con todos los servicios arriba:

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/api/transacciones/resumen-con-intereses/133
curl -H "Authorization: Bearer $TOKEN" http://localhost:8083/api/intereses/resumen-con-cuenta/103
curl -H "Authorization: Bearer $TOKEN" http://localhost:8084/api/cuentas/resumen-con-transaccion/1
```

Cada respuesta debe traer `"fallback":false` (llamada real al servicio downstream vía Feign + Eureka).

Para forzar el fallback, detener un servicio downstream (por ejemplo `intereses-service`) y repetir la llamada en `transacciones-service`:

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/api/transacciones/resumen-con-intereses/133
# -> {"fallback":true, ...}

curl -H "Authorization: Bearer $TOKEN" http://localhost:8082/actuator/circuitbreakers
# -> el estado de "interesesClient" cambia de CLOSED a OPEN/HALF_OPEN tras varios fallos
```

## Referencia de endpoints

### auth-service (8081)

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| POST | `/oauth2/token` | client auth (Basic) | Emite access token (`client_credentials`, `authorization_code`, `refresh_token`) |
| GET | `/oauth2/authorize` | sesión de usuario | Inicio del flujo Authorization Code (login + consentimiento) |
| GET | `/oauth2/jwks` | pública | Clave pública RSA (JWKS) para validar tokens |
| POST | `/oauth2/introspect` | client auth (Basic) | Introspección de un token |
| GET | `/userinfo` | Bearer | Claims OIDC del usuario |
| GET | `/.well-known/openid-configuration` | pública | Metadatos OIDC |

### transacciones-service (8082) / intereses-service (8083) / cuentas-service (8084)

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/api/<recurso>` | Bearer, scope `read` | Listado paginado de los datos migrados |
| GET | `/api/<recurso>/{id}` | Bearer, scope `read` | Registro por id interno |
| GET | `/api/migracion/status` | Bearer, scope `read` | Contadores `leidos/escritos/omitidos` |
| POST | `/api/migracion/rerun` | Bearer + rol `ADMIN` | Re-ejecuta el job de migración |

`<recurso>` es `transacciones`, `intereses` o `cuentas` según el servicio.

Endpoints adicionales de resumen y llamada cross-service:

| Servicio | Ruta | Descripción |
|---|---|---|
| transacciones-service | `GET /api/transacciones/resumen-con-intereses/{cuentaId}` | Llama a `intereses-service` (Circuit Breaker + Retry + fallback) |
| intereses-service | `GET /api/intereses/resumen/{cuentaId}` | Resumen propio (consumido por transacciones-service) |
| intereses-service | `GET /api/intereses/resumen-con-cuenta/{cuentaId}` | Llama a `cuentas-service` (Circuit Breaker + Retry + fallback) |
| cuentas-service | `GET /api/cuentas/resumen/{cuentaId}` | Resumen propio agregado (consumido por intereses-service) |
| cuentas-service | `GET /api/cuentas/resumen-con-transaccion/{transaccionId}` | Llama a `transacciones-service` (Circuit Breaker + Retry + fallback) |

## Stack técnico

- Java 17, Maven multi-módulo
- Spring Boot 3.3.13 / Spring Cloud 2023.0.6 ("Leyton")
- Spring Cloud Config, Netflix Eureka, OpenFeign, LoadBalancer
- Resilience4j 2.4.0 (Circuit Breaker, Retry)
- Spring Security + Spring Authorization Server (OAuth 2.0 / OIDC, JWT RS256 + JWKS) y OAuth2 Resource Server
- Apache Kafka 3.8 (KRaft) con Spring Kafka
- Docker / Docker Compose (imágenes multi-etapa)
- Spring Batch + Spring Data JPA + H2 (una base en memoria por servicio)

## Datos legacy originales

Los archivos en `data/` representan los distintos tipos de datos legacy usados en los procesos batch, organizados por semana (`semana_1`, `semana_2`, `semana_3`). Los microservicios usan `data/semana_3` (el dataset más completo) como fuente.

### Problemas simulados en los datos

- **Montos negativos o cero**: anomalías que requieren validación.
- **Formatos de fecha inconsistentes**: mezcla de `yyyy-MM-dd`, `yyyy/MM/dd`, `dd-MM-yyyy`, `dd/MM/yyyy`, incluyendo fechas inválidas (ej. `2024-13-01`).
- **Datos faltantes o nulos**: campos como saldo o descripción vacíos.
- **Registros duplicados**: múltiples filas con los mismos datos.
- **Valores fuera de rango**: edades no realistas o tipos de transacción/cuenta no válidos.

Estos problemas se gestionan mediante políticas de skip de Spring Batch en cada microservicio para garantizar la integridad y calidad de los datos migrados.
