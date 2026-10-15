ARG AGENT_BASE_IMAGE=jenkins/inbound-agent:jdk21@sha256:64a27e807d216d527a7f5224e6ff9733b5cbd8650db3b5dfd0aea3b94949460f
FROM ${AGENT_BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

ARG NODE_MAJOR=22
ARG DOTNET_CHANNEL=10.0

RUN . /etc/os-release \
    && [[ "$ID" == debian && ( "$VERSION_ID" == 12 || "$VERSION_ID" == 13 ) ]] \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip build-essential python3 pkg-config \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && printf 'deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/adoptium.list \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_%s.x nodistro main\n' "$NODE_MAJOR" > /etc/apt/sources.list.d/nodesource.list \
    && curl -fsSL "https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb" -o /tmp/microsoft-prod.deb \
    && dpkg -i /tmp/microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-17-jdk temurin-21-jdk maven nodejs "dotnet-sdk-$DOTNET_CHANNEL" \
    && mkdir -p /opt/jdks /home/jenkins/agent /home/jenkins/cache \
    && ln -s /usr/lib/jvm/temurin-17-jdk-* /opt/jdks/java17 \
    && ln -s /usr/lib/jvm/temurin-21-jdk-* /opt/jdks/java21 \
    && chown -R jenkins:jenkins /home/jenkins/agent /home/jenkins/cache \
    && rm -rf /var/lib/apt/lists/* /tmp/microsoft-prod.deb

ENV JAVA17_HOME=/opt/jdks/java17 \
    JAVA21_HOME=/opt/jdks/java21 \
    JAVA_HOME=/opt/jdks/java21 \
    JENKINS_JAVA_BIN=/opt/java/openjdk/bin/java \
    MAVEN_OPTS=-Dmaven.repo.local=/home/jenkins/cache/maven \
    GRADLE_USER_HOME=/home/jenkins/cache/gradle \
    npm_config_cache=/home/jenkins/cache/npm \
    NUGET_PACKAGES=/home/jenkins/cache/nuget \
    DOTNET_CLI_HOME=/home/jenkins/cache/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1
ENV PATH="/opt/jdks/java21/bin:${PATH}"

COPY --chmod=0755 start.sh /usr/local/bin/start-build-agent

USER jenkins
WORKDIR /home/jenkins/agent
ENTRYPOINT ["/usr/local/bin/start-build-agent"]