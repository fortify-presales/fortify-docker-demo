#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.env}
LOCAL=false
for option in "$@"; do
	case "$option" in
		--local) LOCAL=true; ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.local.env} ;;
		*) printf 'Usage: %s [--local]\n' "$0" >&2; exit 1 ;;
	esac
done

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" --profile jenkins)
if $LOCAL; then
	COMPOSE+=(-f "$ROOT_DIR/docker-compose.local.yml")
fi
"${COMPOSE[@]}" config --quiet
docker network inspect ftfydemo_net >/dev/null 2>&1 || docker network create ftfydemo_net >/dev/null
"${COMPOSE[@]}" up -d --wait --wait-timeout 900 traefik jenkins

SECRET_FILE="$ROOT_DIR/jenkins/secrets/agent-secret"
if [[ ! -s "$SECRET_FILE" ]]; then
	printf 'Jenkins controller is ready. Complete its setup wizard and register an inbound build agent.\n'
	printf 'Store its secret in %s, readable by UID 1000, then rerun this script. See README.md.\n' "$SECRET_FILE"
	exit 0
fi
if $LOCAL && [[ ! -s "$ROOT_DIR/certs/mkcert-rootCA.pem" ]]; then
	printf 'Run scripts/setup-local.sh before starting the local agent.\n' >&2
	exit 1
fi
"${COMPOSE[@]}" build jenkins-agent
"${COMPOSE[@]}" run --rm --no-deps --entrypoint bash jenkins-agent \
	-c 'test -s /run/secrets/agent-secret && test -r /run/secrets/agent-secret' || {
	printf 'The agent-secret file must be readable by container UID 1000.\n' >&2
	exit 1
}
"${COMPOSE[@]}" up -d --no-deps jenkins-agent
printf 'Build agent started. Confirm it is online in Manage Jenkins > Nodes.\n'
