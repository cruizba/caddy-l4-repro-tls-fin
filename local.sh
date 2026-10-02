#!/usr/bin/env bash
# Same reproduction without Docker: builds a Caddy binary with xcaddy and runs
# everything on the host.
#
#   ./local.sh                              upstream master
#   ./local.sh /path/to/caddy-l4            a local checkout
#   ./local.sh github.com/mholt/caddy-l4@v0.1.2
#
# Needs Go and socat. Caddy's admin API listens on $ADMIN (default 127.0.0.1:2999).
# Uses xcaddy if it is on PATH, otherwise runs it with go run.
set -euo pipefail
cd "$(dirname "$0")"

L4=${1:-github.com/mholt/caddy-l4@master}
XCADDY=(xcaddy)
command -v xcaddy >/dev/null || XCADDY=(go run github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.7)

work=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

case "$L4" in
  /*|./*|../*) with=(--with "github.com/mholt/caddy-l4=$(cd "$L4" && pwd)") ;;
  *)           with=(--with "$L4") ;;
esac
echo ">>> building Caddy with ${with[*]}"
"${XCADDY[@]}" build v2.11.4 --output "$work/caddy" "${with[@]}" >"$work/build.log" 2>&1 || { cat "$work/build.log"; exit 1; }
(cd client && go build -o "$work/client" .)

ADMIN=${ADMIN:-127.0.0.1:2999}
sed -e 's/upstream:9000/127.0.0.1:9000/' -e 's/":8443"/"127.0.0.1:8443"/' \
    -e "1s|{|{\"admin\": {\"listen\": \"$ADMIN\"},|" caddy/caddy.json >"$work/caddy.json"
socat TCP-LISTEN:9000,bind=127.0.0.1,fork,reuseaddr SYSTEM:'echo hello' & pids+=($!)
XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" \
  "$work/caddy" run --config "$work/caddy.json" >"$work/caddy.log" 2>&1 & pids+=($!)
until grep -q 'serving initial configuration' "$work/caddy.log" 2>/dev/null; do
  kill -0 "${pids[1]}" 2>/dev/null || { cat "$work/caddy.log"; exit 1; }
  sleep 0.2
done

"$work/client" -addr 127.0.0.1:8443
