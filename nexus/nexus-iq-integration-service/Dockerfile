FROM eclipse-temurin:17-jre-jammy

RUN apt-get update && apt-get install -y --no-install-recommends curl \
	&& rm -rf /var/lib/apt/lists/* \
	&& groupadd --gid 1000 integration \
	&& useradd --uid 1000 --gid integration --no-create-home integration \
	&& mkdir -p /var/nexus-iq-integration-service \
	&& chown integration:integration /var/nexus-iq-integration-service

WORKDIR /app
COPY files/SonatypeFortifyIntegration-6.0.1.jar ./integration.jar
COPY files/start.sh files/iqapplication.properties files/mapping.json ./
RUN chmod 755 start.sh

USER integration
EXPOSE 8182
ENTRYPOINT ["./start.sh"]