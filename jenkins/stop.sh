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
"${COMPOSE[@]}" stop jenkins-agent
"${COMPOSE[@]}" stop jenkins
