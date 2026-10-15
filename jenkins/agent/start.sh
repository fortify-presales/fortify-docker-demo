#!/usr/bin/env bash
set -Eeuo pipefail

SECRET_FILE=/run/secrets/agent-secret
[[ -s "$SECRET_FILE" && -r "$SECRET_FILE" ]] || {
  printf 'Register the Jenkins build agent and provide a readable agent-secret file.\n' >&2
  exit 1
}

export JENKINS_SECRET="@$SECRET_FILE"
export JENKINS_WEB_SOCKET=true
export JENKINS_AGENT_WORKDIR=/home/jenkins/agent

if [[ -n "${JENKINS_AGENT_CA_FILE:-}" ]]; then
  [[ -s "$JENKINS_AGENT_CA_FILE" && -r "$JENKINS_AGENT_CA_FILE" ]] || {
    printf 'Agent CA certificate is missing or unreadable; rerun scripts/setup-local.sh.\n' >&2
    exit 1
  }
  set -- "$@" -cert "@$JENKINS_AGENT_CA_FILE"
fi

exec /usr/local/bin/jenkins-agent "$@"