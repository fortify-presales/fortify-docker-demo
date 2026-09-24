#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCDAST_DIR="$ROOT_DIR/scdast"
SETTINGS_FILE="$SCDAST_DIR/settings.yaml.template"
SECRETS_DIR="$SCDAST_DIR/secrets"
GENERATED_DIR="$SCDAST_DIR/generated"
MANIFEST_FILE="$GENERATED_DIR/manifest.env"
RUNTIME_ENV_FILE="$GENERATED_DIR/runtime.env"
CORE_RUNTIME_ENV_FILE="$GENERATED_DIR/core-runtime.env"
SCANNER_RUNTIME_ENV_FILE="$GENERATED_DIR/scanner-runtime.env"
SCANNER_SERVICE_RUNTIME_ENV_FILE="$GENERATED_DIR/scanner-service-runtime.env"
TWOFA_RUNTIME_ENV_FILE="$GENERATED_DIR/twofa-runtime.env"
FORTIFYCONNECT_RUNTIME_ENV_FILE="$GENERATED_DIR/fortifyconnect-runtime.env"
DEMO_ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.env}
NETWORK_NAME=ftfydemo_net

COMPOSE_FILES=(--file "$ROOT_DIR/docker-compose.yml")
if [[ -n "${SCDAST_COMPOSE_OVERRIDE:-}" ]]; then
  COMPOSE_FILES+=(--file "$SCDAST_COMPOSE_OVERRIDE")
fi
COMPOSE=(docker compose --project-directory "$ROOT_DIR" "${COMPOSE_FILES[@]}" --env-file "$DEMO_ENV_FILE" --profile scdast)
DAST_SERVICES=(
  scancentral-dast-scannerservice
  scdast-scanner
  scdast-twofa
  scdast-wise
  scdast-datastore
  scancentral-dast-utilityservice
  scdast-scanner-core
  scdast-wise-core
  scdast-datastore-core
  scancentral-dast-globalservice
  scancentral-dast-fortifyconnect
  scancentral-dast-api
)

usage() {
  cat <<'EOF'
Usage: scdast/manage.sh <command> [option]

Commands:
  init                  Configure a new ScanCentral DAST database
  manage                Apply non-upgrade configuration changes
  upgrade --backup-complete
                        Upgrade the database after a verified backup
  validate              Validate prerequisites and generated state
  up                    Start the complete scdast profile
  down                  Stop the complete scdast profile
  reset --confirm       Drop only the DAST database/role and generated state
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

load_environment() {
  set -a
  # shellcheck disable=SC1090
  source "$DEMO_ENV_FILE"
  set +a

  : "${SCDAST_DATABASE_NAME:=scdast}"
  : "${SCDAST_DATABASE_USER:=scdast}"
  : "${SCDAST_DOCKER_VERSION:=26.2.ubi.9}"
  : "${SSC_DAST_USERNAME:=admin}"
  : "${LIM_POOL_NAME:=Default}"
  : "${SCANCENTRAL_DAST_FORTIFYCONNECT_PORT:=2022}"
  : "${SCANCENTRAL_DAST_FORTIFYCONNECT_HOSTNAME:=${SCANCENTRAL_DAST_API_HOSTNAME:-scancentral-dast-api.ftfydemo.localhost}}"
  export SCDAST_DATABASE_NAME SCDAST_DATABASE_USER SCDAST_DOCKER_VERSION
  export SSC_DAST_USERNAME LIM_POOL_NAME SCANCENTRAL_DAST_FORTIFYCONNECT_PORT
  export SCANCENTRAL_DAST_FORTIFYCONNECT_HOSTNAME
}

validate_identifier() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fail "Invalid PostgreSQL identifier: $1"
}

read_secret() {
  local name=$1
  local path="$SECRETS_DIR/$name"
  [[ -f "$path" ]] || fail "Missing secret: $path"
  [[ -s "$path" ]] || fail "Secret is empty: $path"
  tr -d '\r\n' < "$path"
}

read_postgres_admin_password() {
  local path="$ROOT_DIR/postgres/secrets/postgres-admin-password"
  [[ -f "$path" ]] || fail "Missing secret: $path"
  [[ -s "$path" ]] || fail "Secret is empty: $path"
  tr -d '\r\n' < "$path"
}

settings_hash() {
  sha256sum "$SETTINGS_FILE" | cut -d ' ' -f 1
}

write_runtime_environment() {
  local database_password=$1
  local service_token=$2
  local core_datastore_password=$3
  local scanner_datastore_password=$4
  local twofa_master_token=$5
  local fortifyconnect_public_key=$6
  local temp_file

  mkdir -p "$GENERATED_DIR"
  temp_file=$(mktemp "$GENERATED_DIR/runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  {
    printf 'ConnectionStrings__SCDASTDB=Host=postgres;Database=%s;Username=%s;Password=%s;MaxPoolSize=50;\n' "$SCDAST_DATABASE_NAME" "$SCDAST_DATABASE_USER" "$database_password"
    printf 'DBProvider=PostgreSQL\n'
  } > "$temp_file"
  mv "$temp_file" "$RUNTIME_ENV_FILE"

  temp_file=$(mktemp "$GENERATED_DIR/core-runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  {
    printf 'POSTGRES_PASSWORD=%s\n' "$core_datastore_password"
    printf 'WI_SCANDB=Host=scdast-datastore-core;Database=scan_db;Username=postgres;Password=%s;MaxPoolSize=15;\n' "$core_datastore_password"
  } > "$temp_file"
  mv "$temp_file" "$CORE_RUNTIME_ENV_FILE"

  temp_file=$(mktemp "$GENERATED_DIR/scanner-service-runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  {
    printf 'ServiceToken=%s\n' "$service_token"
    printf 'ScannerPoolId=0\n'
  } > "$temp_file"
  mv "$temp_file" "$SCANNER_SERVICE_RUNTIME_ENV_FILE"

  temp_file=$(mktemp "$GENERATED_DIR/scanner-runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  {
    printf 'POSTGRES_PASSWORD=%s\n' "$scanner_datastore_password"
    printf 'WI_SCANDB=Host=scdast-datastore;Database=scan_db;Username=postgres;Password=%s;MaxPoolSize=15;\n' "$scanner_datastore_password"
  } > "$temp_file"
  mv "$temp_file" "$SCANNER_RUNTIME_ENV_FILE"

  temp_file=$(mktemp "$GENERATED_DIR/twofa-runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  printf 'FORTIFY_2FA_MASTER_TOKEN=%s\n' "$twofa_master_token" > "$temp_file"
  mv "$temp_file" "$TWOFA_RUNTIME_ENV_FILE"

  temp_file=$(mktemp "$GENERATED_DIR/fortifyconnect-runtime.env.XXXXXX")
  chmod 600 "$temp_file"
  printf 'PublicKeyContents=%s\n' "$fortifyconnect_public_key" > "$temp_file"
  mv "$temp_file" "$FORTIFYCONNECT_RUNTIME_ENV_FILE"
}

write_manifest() {
  local temp_file
  temp_file=$(mktemp "$GENERATED_DIR/manifest.env.XXXXXX")
  chmod 600 "$temp_file"
  {
    printf 'SCDAST_DOCKER_VERSION=%s\n' "$SCDAST_DOCKER_VERSION"
    printf 'SETTINGS_SHA256=%s\n' "$(settings_hash)"
  } > "$temp_file"
  mv "$temp_file" "$MANIFEST_FILE"
}

assert_current_manifest() {
  local manifest_version
  local manifest_hash
  [[ -f "$MANIFEST_FILE" ]] || fail "DAST is not initialized; run scdast/manage.sh init"
  manifest_version=$(grep '^SCDAST_DOCKER_VERSION=' "$MANIFEST_FILE" | cut -d= -f2-)
  manifest_hash=$(grep '^SETTINGS_SHA256=' "$MANIFEST_FILE" | cut -d= -f2-)
  [[ "$manifest_version" == "$SCDAST_DOCKER_VERSION" ]] || fail "DAST image version changed; run the upgrade command"
  [[ "$manifest_hash" == "$(settings_hash)" ]] || fail "DAST settings changed; run the manage or upgrade command"
  local runtime_file
  for runtime_file in "$RUNTIME_ENV_FILE" "$CORE_RUNTIME_ENV_FILE" "$SCANNER_RUNTIME_ENV_FILE" \
    "$SCANNER_SERVICE_RUNTIME_ENV_FILE" "$TWOFA_RUNTIME_ENV_FILE" "$FORTIFYCONNECT_RUNTIME_ENV_FILE"; do
    [[ -s "$runtime_file" ]] || fail "Missing generated runtime environment: $runtime_file"
  done
}

ensure_network() {
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME" >/dev/null
}

stop_dast_services() {
  "${COMPOSE[@]}" stop "${DAST_SERVICES[@]}" || true
}

load_configuration_secrets() {
  [[ -n "${SSC_DAST_PASSWORD:-}" ]] || fail "SSC_DAST_PASSWORD is not set in demo.env"
  [[ -n "${LIM_PASSWORD:-}" ]] || fail "LIM_PASSWORD is not set in demo.env"
  [[ -n "${LIM_POOL_PASSWORD:-}" ]] || fail "LIM_POOL_PASSWORD is not set in demo.env"
  POSTGRES_ADMIN_PASSWORD=$(read_postgres_admin_password)
  SCDAST_DATABASE_PASSWORD=$(read_secret database-password)
  SCDAST_SERVICE_TOKEN=$(read_secret service-token)
  LIM_SERVICE_PASSWORD=$LIM_PASSWORD
  FORTIFYCONNECT_PRIVATE_KEY_CONTENTS=$(read_secret fortifyconnect-private-key)
  FORTIFYCONNECT_PUBLIC_KEY_CONTENTS=$(read_secret fortifyconnect-public-key)
  export POSTGRES_ADMIN_PASSWORD SCDAST_DATABASE_PASSWORD SCDAST_SERVICE_TOKEN
  export SSC_DAST_PASSWORD LIM_SERVICE_PASSWORD LIM_POOL_PASSWORD
  export FORTIFYCONNECT_PRIVATE_KEY_CONTENTS FORTIFYCONNECT_PUBLIC_KEY_CONTENTS
}

run_configuration() {
  local mode=$1
  docker run --rm \
    --network "$NETWORK_NAME" \
    --volume "$SETTINGS_FILE:/app/settings.yaml:ro" \
    --env POSTGRES_ADMIN_PASSWORD \
    --env SCDAST_DATABASE_NAME \
    --env SCDAST_DATABASE_USER \
    --env SCDAST_DATABASE_PASSWORD \
    --env SCDAST_SERVICE_TOKEN \
    --env SSC_HOSTNAME \
    --env SSC_DAST_USERNAME \
    --env SSC_DAST_PASSWORD \
    --env SCANCENTRAL_DAST_API_HOSTNAME \
    --env LIM_USERNAME \
    --env LIM_SERVICE_PASSWORD \
    --env LIM_POOL_NAME \
    --env LIM_POOL_PASSWORD \
    --env SCANCENTRAL_DAST_FORTIFYCONNECT_HOSTNAME \
    --env SCANCENTRAL_DAST_FORTIFYCONNECT_PORT \
    --env FORTIFYCONNECT_PRIVATE_KEY_CONTENTS \
    --env FORTIFYCONNECT_PUBLIC_KEY_CONTENTS \
    "fortifydocker/scancentral-dast-config:$SCDAST_DOCKER_VERSION" \
    configureEnvironment --mode "$mode" --settingsFile /app/settings.yaml
}

configure() {
  local mode=$1
  load_configuration_secrets
  ensure_network
  "${COMPOSE[@]}" up -d --wait postgres lim ssc
  run_configuration "$mode"
  write_runtime_environment \
    "$SCDAST_DATABASE_PASSWORD" \
    "$SCDAST_SERVICE_TOKEN" \
    "$(read_secret core-datastore-password)" \
    "$(read_secret scanner-datastore-password)" \
    "$(read_secret twofa-master-token)" \
    "$FORTIFYCONNECT_PUBLIC_KEY_CONTENTS"
  write_manifest
}

validate() {
  command -v docker >/dev/null || fail "docker is required"
  docker compose version >/dev/null || fail "Docker Compose v2 is required"
  [[ -f "$SETTINGS_FILE" ]] || fail "Missing settings template"
  validate_identifier "$SCDAST_DATABASE_NAME"
  validate_identifier "$SCDAST_DATABASE_USER"
  assert_current_manifest
  "${COMPOSE[@]}" config --quiet
  printf 'ScanCentral DAST configuration is valid.\n'
}

reset_environment() {
  [[ "${1:-}" == "--confirm" ]] || fail "reset requires --confirm"
  validate_identifier "$SCDAST_DATABASE_NAME"
  validate_identifier "$SCDAST_DATABASE_USER"
  stop_dast_services
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
    -c "DROP DATABASE IF EXISTS \"$SCDAST_DATABASE_NAME\" WITH (FORCE);" \
    -c "DROP ROLE IF EXISTS \"$SCDAST_DATABASE_USER\";"
  find "$GENERATED_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true
  printf 'DAST database, role, and generated state removed. Shared PostgreSQL data was preserved.\n'
}

main() {
  local command=${1:-}
  load_environment

  case "$command" in
    init)
      if [[ -f "$MANIFEST_FILE" ]]; then
        validate
        printf 'ScanCentral DAST is already initialized.\n'
      else
        configure New
      fi
      ;;
    manage)
      [[ -f "$MANIFEST_FILE" ]] || fail "DAST is not initialized; run scdast/manage.sh init"
      stop_dast_services
      configure Manage
      ;;
    upgrade)
      [[ "${2:-}" == "--backup-complete" ]] || fail "upgrade requires --backup-complete"
      stop_dast_services
      configure Upgrade
      ;;
    validate)
      validate
      ;;
    up)
      validate
      "${COMPOSE[@]}" up -d --wait
      ;;
    down)
      stop_dast_services
      ;;
    reset)
      reset_environment "${2:-}"
      ;;
    *)
      usage
      [[ -n "$command" ]] && exit 1
      ;;
  esac
}

main "$@"