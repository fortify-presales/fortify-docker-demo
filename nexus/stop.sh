#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.env}
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" --profile sonatype-integration)
if [[ "${1:-}" == --local ]]; then
	COMPOSE=(docker compose --env-file "${DEMO_ENV_FILE:-$ROOT_DIR/demo.local.env}" \
		-f "$ROOT_DIR/docker-compose.yml" -f "$ROOT_DIR/docker-compose.local.yml" --profile sonatype-integration)
elif [[ $# -gt 0 ]]; then
	printf 'Usage: %s [--local]\n' "$0" >&2
	exit 1
fi
"${COMPOSE[@]}" stop nexus-iq-integration-service nexus-iq-server nexus-repo nexus-init
