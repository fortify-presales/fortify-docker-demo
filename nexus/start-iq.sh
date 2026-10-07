#!/bin/sh
set -eu

DATABASE_PASSWORD=$(cat /run/secrets/database-password)
[ -n "$DATABASE_PASSWORD" ] || { echo 'IQ database password is empty.' >&2; exit 1; }
[ -s /run/secrets/sonatype-license.lic ] && [ -r /run/secrets/sonatype-license.lic ] || {
    echo 'Sonatype license must be non-empty and readable by UID 1000.' >&2
    exit 1
}
export DATABASE_PASSWORD
exec sh /opt/sonatype/nexus-iq-server/start.sh