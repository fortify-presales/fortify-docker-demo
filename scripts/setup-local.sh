#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOCAL_ENV_FILE="$ROOT_DIR/demo.local.env"

command -v mkcert >/dev/null || {
  printf 'Error: mkcert is required. See https://github.com/FiloSottile/mkcert\n' >&2
  exit 1
}

if [[ ! -f "$LOCAL_ENV_FILE" ]]; then
  cp "$ROOT_DIR/demo.local.env.example" "$LOCAL_ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
source "$LOCAL_ENV_FILE"
set +a

mkcert -install
mkdir -p "$ROOT_DIR/certs"
mkcert \
  -cert-file "$ROOT_DIR/certs/ftfydemo.localhost.pem" \
  -key-file "$ROOT_DIR/certs/ftfydemo.localhost-key.pem" \
  "$LIM_HOSTNAME" \
  "$SSC_HOSTNAME" \
  "$SCANCENTRAL_SAST_CONTROLLER_HOSTNAME" \
  "$SCANCENTRAL_DAST_API_HOSTNAME"

docker network inspect ftfydemo_net >/dev/null 2>&1 || docker network create ftfydemo_net >/dev/null

printf 'Local environment prepared in %s\n' "$LOCAL_ENV_FILE"
printf 'Use docker-compose.yml with docker-compose.local.yml and --env-file demo.local.env.\n'