#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.env}
INTEGRATION=false
LOCAL=false
for option in "$@"; do
	case "$option" in
		--integration) INTEGRATION=true ;;
		--local) LOCAL=true; ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.local.env} ;;
		*) printf 'Usage: %s [--local] [--integration]\n' "$0" >&2; exit 1 ;;
	esac
done

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" --profile sonatype)
if $LOCAL; then
	COMPOSE+=(-f "$ROOT_DIR/docker-compose.local.yml")
fi
if $INTEGRATION; then
	COMPOSE+=(--profile sonatype-integration)
	[[ -s "$ROOT_DIR/nexus/secrets/ssc-token" ]] || {
		printf 'Create nexus/secrets/ssc-token with a real SSC CIToken before using --integration.\n' >&2
		exit 1
	}
fi
[[ -s "$ROOT_DIR/sonatype-license.lic" ]] || {
	printf 'Place a valid sonatype-license.lic at the repository root.\n' >&2
	exit 1
}
"${COMPOSE[@]}" config --quiet
umask 077
mkdir -p "$ROOT_DIR/postgres/secrets" "$ROOT_DIR/nexus/secrets"
if [[ ! -e "$ROOT_DIR/postgres/secrets/postgres-admin-password" ]]; then
	openssl rand -hex 32 > "$ROOT_DIR/postgres/secrets/postgres-admin-password"
fi
if [[ ! -e "$ROOT_DIR/nexus/secrets/database-password" ]]; then
	openssl rand -hex 32 > "$ROOT_DIR/nexus/secrets/database-password"
fi
if $INTEGRATION && [[ ! -e "$ROOT_DIR/nexus/secrets/iq-password" ]]; then
	printf '%s' 'admin123' > "$ROOT_DIR/nexus/secrets/iq-password"
	printf 'Created bootstrap IQ integration credential. Update it after changing the IQ password.\n'
fi
POSTGRES_IMAGE=$("${COMPOSE[@]}" config --images | grep '^postgres:' | sort -u)
docker run --rm --user 1000:1000 --entrypoint sh \
	--mount "type=bind,src=$ROOT_DIR/nexus/secrets,dst=/secrets,readonly" \
	--mount "type=bind,src=$ROOT_DIR/sonatype-license.lic,dst=/license,readonly" \
	"$POSTGRES_IMAGE" -c 'test -s /secrets/database-password && test -r /secrets/database-password && test -r /license' || {
	printf 'IQ secrets and license must be readable by container UID 1000. Keep secrets owned by UID 1000 with mode 600.\n' >&2
	exit 1
}
docker network inspect ftfydemo_net >/dev/null 2>&1 || docker network create ftfydemo_net >/dev/null
"${COMPOSE[@]}" up -d --wait --no-recreate traefik postgres
"${COMPOSE[@]}" run --rm --no-deps nexus-init
"${COMPOSE[@]}" up -d --wait --wait-timeout 900 --no-deps nexus-repo nexus-iq-server
if $INTEGRATION; then
	"${COMPOSE[@]}" up -d --wait --no-recreate ssc
	"${COMPOSE[@]}" build nexus-iq-integration-service
	"${COMPOSE[@]}" up -d --wait --wait-timeout 300 --no-deps nexus-iq-integration-service
fi
printf 'Sonatype services are ready. Use the hostnames configured in %s.\n' "$ENV_FILE"
