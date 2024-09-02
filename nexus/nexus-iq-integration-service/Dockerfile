FROM openjdk:11-jdk-slim

LABEL maintainer="klee2@opentext.com"

USER root

# Add docker-compose-wait tool -------------------
ENV WAIT_VERSION 2.7.2
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/$WAIT_VERSION/wait /wait
RUN chmod +x /wait

# Create app directory
WORKDIR /app

# Copy the files to the container
ADD files ./

# Make port 8182 available to the world outside this container
EXPOSE 8182

# JAVA_OPTS to be passed in
#ENV JAVA_OPTS="-Xmx512m -Xss256k"

# Run the jar file
ENTRYPOINT ["./start.sh"]