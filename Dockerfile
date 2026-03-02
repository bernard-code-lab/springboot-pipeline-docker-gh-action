# Stage 1: Build
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Maven wrapper (required for ./mvnw)
COPY mvnw .
COPY .mvn .mvn
RUN chmod +x mvnw

# Dependencies layer: only pom.xml so this layer is cached when only code changes
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw dependency:go-offline -B

# Source and package
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw package -DskipTests -B

# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

ARG ENVIRONMENT
ENV ENVIRONMENT=${ENVIRONMENT}

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

COPY --from=builder /app/target/*.jar app.jar

# curl for HEALTHCHECK (Alpine JRE does not include wget)
USER root
RUN apk add --no-cache curl
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
