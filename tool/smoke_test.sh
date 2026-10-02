#!/bin/sh
# Loads a plugin into a throwaway Pumpkin server (alternate ports, scratch
# directory), feeds it console commands, and prints the server log.
#
# Usage: PUMPKIN_BIN=/path/to/pumpkin tool/smoke_test.sh plugin.wasm [command...]
#
# Set ALLOW_PERMISSIONS to pre-approve plugin permissions.
# Set PORT_OFFSET (e.g. 100) to run several smoke tests at the same time.
#
# Each command is typed into the server console one second apart, after the
# server has started. `stop` is appended automatically.
set -e

WASM="$1"; shift
: "${PUMPKIN_BIN:?set PUMPKIN_BIN to a pumpkin server binary (release builds start much faster)}"
: "${PUMPKIN_CONFIG:=$(dirname "$PUMPKIN_BIN")/../../pumpkin.toml}"
: "${STARTUP_SECONDS:=14}"
: "${PORT_OFFSET:=0}"
JAVA=$((35565 + PORT_OFFSET)); RCON=$((35575 + PORT_OFFSET)); BEDROCK=$((29132 + PORT_OFFSET))

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
mkdir -p "$DIR/plugins"
cp "$WASM" "$DIR/plugins/"
sed -e "s/0.0.0.0:25565/0.0.0.0:$JAVA/; s/0.0.0.0:25575/0.0.0.0:$RCON/; s/0.0.0.0:19132/0.0.0.0:$BEDROCK/" \
  "$PUMPKIN_CONFIG" > "$DIR/pumpkin.toml"

# Plugins that request permissions are normally approved interactively, which a
# scripted run can't do. ALLOW_PERMISSIONS="fs.write.data fs.read.data" grants
# them up front.
if [ -n "$ALLOW_PERMISSIONS" ]; then
  LIST=$(for permission in $ALLOW_PERMISSIONS; do printf '"%s", ' "$permission"; done)
  sed -i.bak "s/^allowed_permissions = .*/allowed_permissions = [${LIST%, }]/" "$DIR/pumpkin.toml"
fi

cd "$DIR"
(
  sleep "$STARTUP_SECONDS"
  for command in "$@"; do echo "$command"; sleep 1; done
  echo stop
  sleep 3
) | timeout 180 "$PUMPKIN_BIN" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'

# SHOW_FILES=1 lists what the plugins left under plugins/data.
if [ -n "$SHOW_FILES" ]; then
  echo "--- files under plugins/data:"
  (cd "$DIR/plugins" && find data -type f 2>/dev/null | sort) || true
fi
