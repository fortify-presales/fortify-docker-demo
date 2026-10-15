#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCAL=false
FORCE=false
TIMEOUT=180
PROFILES=()

usage() {
	cat <<'EOF'
Usage: ./stop.sh [--local] [--profile NAME]... [--timeout SECONDS] [--force]

Stop the demo stack gracefully. Containers, named volumes, and all
persistent data are preserved, so the stack can be restarted with
./start.sh.

Options:
  --local            Use demo.local.env and docker-compose.local.yml
  --profile NAME     Stop only this profile; repeat for several.
                     Defaults to every configured profile.
  --timeout SECONDS  Grace period per container (default: 180)
  --force            Skip the interactive confirmation
  -h, --help         Show this help

Before stopping, let running Jenkins builds, SAST jobs, and DAST scans
finish so they are not interrupted mid-write.
EOF
}

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--local) LOCAL=true ;;
		--force) FORCE=true ;;
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

command -v docker >/dev/null || fail 'docker is required.'
docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is required.'
[[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE."

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml")
$LOCAL && COMPOSE+=(-f "$ROOT_DIR/docker-compose.local.yml")
[[ ${#PROFILES[@]} -gt 0 ]] || PROFILES=('*')
for profile in "${PROFILES[@]}"; do
	COMPOSE+=(--profile "$profile")
done

"${COMPOSE[@]}" config --quiet || fail 'Compose configuration is invalid.'

if ! $FORCE; then
	if [[ ! -t 0 ]]; then
		fail 'Refusing to stop non-interactively without --force (stdin is not a terminal).'
	fi
	printf 'Stop the stack now? Running builds and scans will be interrupted. [y/N] '
	read -r reply
	[[ "$reply" =~ ^[Yy]$ ]] || { printf 'Aborted.\n'; exit 0; }
fi

printf 'Stopping services with a %ss grace period.\n' "$TIMEOUT"
"${COMPOSE[@]}" stop --timeout "$TIMEOUT"

remaining=$("${COMPOSE[@]}" ps --status running --quiet | wc -l)
if [[ "$remaining" -gt 0 ]]; then
	printf '\nWarning: %s container(s) are still running.\n' "$remaining" >&2
	"${COMPOSE[@]}" ps --status running
	exit 1
fi

printf '\nAll services stopped. Data volumes are preserved; restart with ./start.sh\n'
