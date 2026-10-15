#!/bin/sh
#
# Copyright (c) 2020-present Sonatype, Inc. All rights reserved.
# Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
# "Sonatype" is a trademark of Sonatype, Inc.
# 

set -eu

if [ -z "${IQSERVER_PASSWORD:-}" ]; then
	IQSERVER_PASSWORD=$(cat "${IQSERVER_PASSWORD_FILE:-/run/secrets/iq-password}")
fi
if [ -z "${SSCSERVER_TOKEN:-}" ]; then
	SSCSERVER_TOKEN=$(cat "${SSCSERVER_TOKEN_FILE:-/run/secrets/ssc-token}")
fi
[ -n "$IQSERVER_PASSWORD" ] || { echo 'IQ password is empty.' >&2; exit 1; }
[ -n "$SSCSERVER_TOKEN" ] || { echo 'SSC CIToken is empty.' >&2; exit 1; }
export IQSERVER_PASSWORD SSCSERVER_TOKEN

set -- -Djava.util.prefs.userRoot=/var/nexus-iq-integration-service/javaprefs
if [ -n "${IQSERVER_CA_FILE:-}" ]; then
	[ -s "$IQSERVER_CA_FILE" ] && [ -r "$IQSERVER_CA_FILE" ] || {
		echo 'IQ server CA certificate is missing or unreadable; rerun scripts/setup-local.sh.' >&2
		exit 1
	}
	truststore=/tmp/iqserver-truststore
	cp "$JAVA_HOME/lib/security/cacerts" "$truststore"
	chmod 600 "$truststore"
	keytool -importcert -noprompt -trustcacerts -alias iqserver-ca \
		-file "$IQSERVER_CA_FILE" -keystore "$truststore" -storepass changeit >/dev/null
	set -- "$@" "-Djavax.net.ssl.trustStore=$truststore" \
		-Djavax.net.ssl.trustStorePassword=changeit
fi

exec java "$@" -jar /app/integration.jar \
	--spring.config.additional-location=file:/app/iqapplication.properties
