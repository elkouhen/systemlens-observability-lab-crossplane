FROM maven:3.9.9-eclipse-temurin-21 AS build

ARG OTEL_JAVA_AGENT_VERSION=2.28.1
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent), encodé en
# base64. Laisser vide sur une machine sans interception TLS.
ARG ZSCALER_CA_CERT_B64=""

WORKDIR /workspace

RUN if [ -n "$ZSCALER_CA_CERT_B64" ]; then \
      echo "$ZSCALER_CA_CERT_B64" | base64 -d > /usr/local/share/ca-certificates/zscaler-root-ca.crt && \
      update-ca-certificates && \
      keytool -importcert -noprompt -trustcacerts -alias zscaler-root-ca \
        -file /usr/local/share/ca-certificates/zscaler-root-ca.crt \
        -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit; \
    fi

COPY pom.xml ./
RUN mvn --batch-mode dependency:go-offline
COPY src src
RUN mvn --batch-mode package -DskipTests
RUN curl --fail --location --silent --show-error \
  "https://repo1.maven.org/maven2/io/opentelemetry/javaagent/opentelemetry-javaagent/${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent-${OTEL_JAVA_AGENT_VERSION}.jar" \
  -o /opt/opentelemetry-javaagent.jar

# L'agent Java OpenTelemetry est le seul agent d'instrumentation, attaché par
# l'ENTRYPOINT (traces, logs et métriques JVM). Le déploiement Kubernetes ne fait que le
# configurer. Hors Kubernetes, OTEL_SERVICE_NAME donne l'identité du service.
FROM eclipse-temurin:21.0.7_6-jre-noble AS demo-api

WORKDIR /app
COPY --from=build /workspace/target/demo-api-1.1.0.jar application.jar
ENV OTEL_SERVICE_NAME=demo-api
COPY --from=build /opt/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar
USER 10001
EXPOSE 3010
ENTRYPOINT ["java", "-javaagent:/opt/opentelemetry-javaagent.jar", "-jar", "/app/application.jar"]
