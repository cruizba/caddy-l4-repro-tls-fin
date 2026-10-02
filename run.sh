#!/usr/bin/env bash
# Builds Caddy with caddy-l4 from a git repository and branch, then reproduces the
# missing TCP FIN after close_notify with Docker Compose.
#
#   ./run.sh                                                         upstream master
#   ./run.sh https://github.com/cruizba/caddy-l4 fix/tls-close-write-fin
#
# Exit status: 0 when Caddy sends the FIN, 1 when it does not.
set -euo pipefail
cd "$(dirname "$0")"

export CADDY_L4_REPO=${1:-https://github.com/mholt/caddy-l4}
export CADDY_L4_REF=${2:-master}
export COMPOSE_PROJECT_NAME=caddy-l4-repro-tls-fin
trap 'docker compose --profile client down -t 1 >/dev/null 2>&1' EXIT

echo ">>> building Caddy with caddy-l4 ${CADDY_L4_REPO} ${CADDY_L4_REF}"
docker compose --profile client build -q
docker compose up -d upstream caddy tcpdump
until docker compose logs caddy 2>/dev/null | grep -q 'serving initial configuration'; do sleep 0.5; done
docker compose logs --no-log-prefix caddy | grep '^caddy-l4:'
sleep 1

set +e
docker compose run --rm client
status=$?
set -e

sleep 1
echo ">>> FIN/RST packets on caddy:8443 (the client closes after its hold time):"
docker compose logs --no-log-prefix tcpdump | grep 'Flags' || echo "(none)"
exit "$status"
