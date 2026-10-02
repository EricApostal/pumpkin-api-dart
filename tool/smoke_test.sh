#!/bin/sh
# Loads a plugin into a throwaway Pumpkin server (alternate ports, scratch
# directory), feeds it console commands, and prints the server log.
#
# Usage: PUMPKIN_BIN=/path/to/pumpkin tool/smoke_test.sh plugin.wasm [command...]
#
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

cd "$DIR"
(
  sleep "$STARTUP_SECONDS"
  for command in "$@"; do echo "$command"; sleep 1; done
  echo stop
  sleep 3
) | timeout 180 "$PUMPKIN_BIN" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
