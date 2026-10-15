#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-$(basename "$ROOT_DIR")}
LOCAL=false
TIMEOUT=900
PROFILES=()

usage() {
	cat <<'EOF'
Usage: ./start.sh [--local] [--profile NAME]... [--timeout SECONDS]

Start the demo stack and wait until services report ready.

Options:
  --local            Use demo.local.env and docker-compose.local.yml
  --profile NAME     Start only this profile; repeat for several.
                     Defaults to every configured profile.
  --timeout SECONDS  Readiness timeout (default: 900)
  -h, --help         Show this help

Examples:
  ./start.sh
  ./start.sh --profile default --profile jenkins
  ./start.sh --local
EOF
}

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

require_file() {
	[[ -s "$1" ]] || fail "$2"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--local) LOCAL=true ;;
		--profile)
			[[ -n "${2:-}" ]] || fail '--profile requires a value.'
			PROFILES+=("$2")
			shift
			;;
		--timeout)
			[[ "${2:-}" =~ ^[0-9]+$ ]] || fail '--timeout requires a number of seconds.'
			TIMEOUT=$2
			shift
			;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 1 ;;
	esac
	shift
done

if $LOCAL; then
	ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.local.env}
else
	ENV_FILE=${DEMO_ENV_FILE:-$ROOT_DIR/demo.env}
fi

# Local and production share one Compose project, so running the wrong mode would
# recreate the existing containers with the other mode's settings. Containers record
# the overrides that created them, which lets us refuse before any change is made.
check_mode_conflict() {
	local id labels running_local
	for id in $(docker ps --quiet --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null); do
		labels=$(docker inspect "$id" \
			--format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null) || continue
		case "$labels" in
			*docker-compose.local.yml*) running_local=true ;;
			*) running_local=false ;;
		esac
		if [[ "$running_local" != "$LOCAL" ]]; then
			local mode='production'
			local stop_cmd='./stop.sh'
			if $running_local; then
				mode='local'
				stop_cmd='./stop.sh --local'
			fi
			fail "This stack is already running in $mode mode. Stop it with $stop_cmd before switching modes."
		fi
	done
}

command -v docker >/dev/null || fail 'docker is required.'
docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is required.'

if [[ ! -f "$ENV_FILE" ]]; then
	if $LOCAL; then
		fail "Missing $ENV_FILE. Run ./scripts/setup-local.sh first."
	fi
	fail "Missing $ENV_FILE."
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml")
$LOCAL && COMPOSE+=(-f "$ROOT_DIR/docker-compose.local.yml")
[[ ${#PROFILES[@]} -gt 0 ]] || PROFILES=('*')
for profile in "${PROFILES[@]}"; do
	COMPOSE+=(--profile "$profile")
done

"${COMPOSE[@]}" config --quiet || fail 'Compose configuration is invalid.'

check_mode_conflict

mapfile -t SERVICES < <("${COMPOSE[@]}" config --services | sort)
[[ ${#SERVICES[@]} -gt 0 ]] || fail 'No services matched the selected profiles.'

selected() {
	local service
	for service in "${SERVICES[@]}"; do
		[[ "$service" == "$1" ]] && return 0
	done
	return 1
}

require_file "$ROOT_DIR/fortify.license" 'Place a valid fortify.license at the repository root.'

if selected nexus-repo || selected nexus-iq-server; then
	require_file "$ROOT_DIR/sonatype-license.lic" 'Place a valid sonatype-license.lic at the repository root.'
fi

if selected nexus-iq-integration-service; then
	require_file "$ROOT_DIR/nexus/secrets/ssc-token" \
		'Create nexus/secrets/ssc-token with a real SSC CIToken before starting the integration.'
	require_file "$ROOT_DIR/nexus/secrets/iq-password" \
		'Create nexus/secrets/iq-password with the current IQ password.'
fi

if selected jenkins-agent; then
	require_file "$ROOT_DIR/jenkins/secrets/agent-secret" \
		'Register the Jenkins agent and store its secret in jenkins/secrets/agent-secret.'
fi

if selected scancentral-dast-api; then
	[[ -f "$ROOT_DIR/scdast/generated/manifest.env" ]] || \
		fail 'ScanCentral DAST is not initialized; run ./scdast/manage.sh init first.'
fi

# The local Jenkins agent and IQ integration trust Traefik through the mkcert root CA.
if $LOCAL && { selected jenkins-agent || selected nexus-iq-integration-service; }; then
	require_file "$ROOT_DIR/certs/mkcert-rootCA.pem" \
		'Missing certs/mkcert-rootCA.pem. Run ./scripts/setup-local.sh first.'
fi

docker network inspect ftfydemo_net >/dev/null 2>&1 || docker network create ftfydemo_net >/dev/null

# ssc-init and nexus-init are one-shot bootstrap containers. Compose runs them through
# depends_on, and --wait would treat their expected exit as a startup failure.
mapfile -t WAIT_SERVICES < <(printf '%s\n' "${SERVICES[@]}" | grep -v -- '-init$')
[[ ${#WAIT_SERVICES[@]} -gt 0 ]] || fail 'No long-running services matched the selected profiles.'

printf 'Starting %d services using %s (timeout %ss).\n' "${#WAIT_SERVICES[@]}" "$(basename "$ENV_FILE")" "$TIMEOUT"
"${COMPOSE[@]}" up -d --wait --wait-timeout "$TIMEOUT" "${WAIT_SERVICES[@]}"

printf '\nStack is ready.\n\n'
"${COMPOSE[@]}" ps
