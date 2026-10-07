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

exec java -Djava.util.prefs.userRoot=/var/nexus-iq-integration-service/javaprefs \
	-jar /app/integration.jar --spring.config.additional-location=file:/app/iqapplication.properties
