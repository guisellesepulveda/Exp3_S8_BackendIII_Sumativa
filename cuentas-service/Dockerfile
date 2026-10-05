# syntax=docker/dockerfile:1
# Imagen de cuentas-service. Contexto de build = raiz del repo (necesita el pom padre y common-lib):
#   docker build -f cuentas-service/Dockerfile -t banco-xyz/cuentas-service:1.0.0 .

# ---- Etapa 1: compilacion (Maven + JDK 17) ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace

# Los pom de TODOS los modulos deben existir: el pom padre los lista en <modules>.
COPY pom.xml ./
COPY common-lib/pom.xml common-lib/
COPY config-server/pom.xml config-server/
COPY discovery-server/pom.xml discovery-server/
COPY auth-service/pom.xml auth-service/
COPY transacciones-service/pom.xml transacciones-service/
COPY intereses-service/pom.xml intereses-service/
COPY cuentas-service/pom.xml cuentas-service/

COPY common-lib/src common-lib/src
COPY cuentas-service/src cuentas-service/src

# -am compila tambien common-lib; la cache de ~/.m2 se conserva entre builds.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp -q -pl cuentas-service -am clean package -DskipTests

# ---- Etapa 2: runtime (solo JRE, usuario sin privilegios) ----
FROM eclipse-temurin:17-jre
RUN useradd --system --create-home app
WORKDIR /app
COPY --from=build /workspace/cuentas-service/target/cuentas-service-1.0.0.jar app.jar
USER app

EXPOSE 8084
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
