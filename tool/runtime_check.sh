#!/bin/sh
# Builds example/hello_plugin/bin/runtime_check.dart and runs every `t <name>`
# check on a throwaway Pumpkin server, failing if any check fails or traps.
#
# Usage: PUMPKIN_BIN=/path/to/pumpkin [DART="puro dart"] tool/runtime_check.sh
set -e
cd "$(dirname "$0")/.."

: "${PUMPKIN_BIN:?set PUMPKIN_BIN to a pumpkin server binary}"
DART="${DART:-dart}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

(cd example/hello_plugin && $DART run pumpkin_tools build bin/runtime_check.dart -o "$OUT/runtime_check.wasm")

CHECKS=$(grep -oE "^  '[A-Za-z_0-9]+':" example/hello_plugin/bin/runtime_check.dart | tr -d " ':")
set --
for check in $CHECKS; do set -- "$@" "t $check"; done

tool/smoke_test.sh "$OUT/runtime_check.wasm" "$@" > "$OUT/log" 2>&1 || true
grep -E "RT (OK|FAIL)" "$OUT/log" | sed 's/^.*\[plugin\] //'

PASSED=$(grep -c "RT OK" "$OUT/log" || true)
TOTAL=$(echo "$CHECKS" | wc -l | tr -d ' ')
echo "$PASSED of $TOTAL checks passed"
[ "$PASSED" = "$TOTAL" ] && ! grep -q "RT FAIL\| ERROR " "$OUT/log"
