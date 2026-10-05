#!/bin/sh
# Starts a throwaway OFFLINE-mode Pumpkin server (no encryption, alternate
# port, scratch working directory), waits until it accepts connections, runs
# the given command, and ALWAYS stops the server again.
#
# Usage:
#   PUMPKIN_BIN=/path/to/pumpkin ./with_server.sh python3 modbridge_client.py --port 35965 --vanilla
#
# Environment:
#   PUMPKIN_BIN     server binary (default: ../../../../../rust/Pumpkin/target/release/pumpkin)
#   PUMPKIN_CONFIG  config to start from (default: pumpkin.toml next to target/ of the binary)
#   PORT            Java port (default 35965); the command is told via $PORT
#   PLUGINS         space separated .wasm files copied into the server's plugins/
#   ALLOW_PERMISSIONS  space separated plugin permissions to pre-approve
#   SERVER_LOG      where to write the server log (default: <scratch>/server.log, printed at the end)
#   STARTUP_TIMEOUT seconds to wait for the port (default 90)
set -u

ORIG="$PWD"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${PUMPKIN_BIN:=$HERE/../../../../../rust/Pumpkin/target/release/pumpkin}"
: "${PUMPKIN_CONFIG:=$(dirname "$PUMPKIN_BIN")/../../pumpkin.toml}"
: "${PORT:=35965}"
: "${STARTUP_TIMEOUT:=90}"
export PORT

DIR="$(mktemp -d)"
: "${SERVER_LOG:=$DIR/server.log}"
mkdir -p "$DIR/plugins"
for wasm in ${PLUGINS:-}; do cp "$wasm" "$DIR/plugins/"; done

# offline mode, no encryption, own port, no bedrock/rcon/query
sed -e "/^\[networking.java\]/,/^\[/{s|^address = .*|address = \"127.0.0.1:$PORT\"|;s|^encryption = .*|encryption = false|;s|^online_mode = .*|online_mode = false|;}" \
    -e "/^\[networking.bedrock\]/,/^\[/{s|^enabled = .*|enabled = false|;}" \
    -e "/^\[networking.bedrock.nethernet\]/,/^\[/{s|^enabled = .*|enabled = false|;}" \
    -e "/^\[networking.rcon\]/,/^\[/{s|^address = .*|address = \"127.0.0.1:$((PORT + 10))\"|;}" \
    -e "/^\[networking.query\]/,/^\[/{s|^address = .*|address = \"127.0.0.1:$((PORT + 11))\"|;}" \
    "$PUMPKIN_CONFIG" > "$DIR/pumpkin.toml"
if [ -n "${ALLOW_PERMISSIONS:-}" ]; then
  LIST=$(for permission in $ALLOW_PERMISSIONS; do printf '"%s", ' "$permission"; done)
  sed -i.bak "s/^allowed_permissions = .*/allowed_permissions = [${LIST%, }]/" "$DIR/pumpkin.toml"
fi

PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  case "$SERVER_LOG" in "$DIR"/*) cp "$SERVER_LOG" "${TMPDIR:-/tmp}/pumpkin-with-server.log" 2>/dev/null; SERVER_LOG="${TMPDIR:-/tmp}/pumpkin-with-server.log";; esac
  rm -rf "$DIR"
  echo "[with_server] server stopped; log: $SERVER_LOG" >&2
}
trap cleanup EXIT INT TERM

cd "$DIR"
# stdin from /dev/null is fine: the server only needs it for console commands
"$PUMPKIN_BIN" < /dev/null > "$SERVER_LOG" 2>&1 &
PID=$!

i=0
until python3 -c "import socket,sys; socket.create_connection(('127.0.0.1', $PORT), 1).close()" 2>/dev/null; do
  i=$((i + 1))
  if ! kill -0 "$PID" 2>/dev/null || [ "$i" -gt "$STARTUP_TIMEOUT" ]; then
    echo "[with_server] server did not come up; log tail:" >&2
    tail -n 30 "$SERVER_LOG" >&2
    exit 3
  fi
  sleep 1
done
echo "[with_server] server up on 127.0.0.1:$PORT (pid $PID)" >&2

cd "$ORIG"
"$@"
STATUS=$?
sleep 0.5
exit $STATUS
