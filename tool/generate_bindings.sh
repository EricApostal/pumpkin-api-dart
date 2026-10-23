#!/bin/sh
# Regenerates the Dart bindings in packages/pumpkin_api from the WIT: Pumpkin's
# plugin world (the `wit` submodule) plus the WASI imports in `wit-dart`.
# Usage: tool/generate_bindings.sh [wit-version]   (default: v0.2)
#
# Environment:
#   WIT_DIR  a directory with the version's .wit files (for example
#            ~/src/Pumpkin/crates/pumpkin-plugin-wit/v0.2). It replaces
#            `wit/<version>`, to generate bindings for WIT that is not in the
#            submodule yet.
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-v0.2}"

# Stage the world together with Pumpkin's WIT as a dependency.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R wit-dart/. "$STAGE/"
mkdir -p "$STAGE/deps/pumpkin-plugin"
WIT_SOURCE="${WIT_DIR:-wit/$VERSION}"
if [ ! -d "$WIT_SOURCE" ]; then
  echo "WIT directory not found: $WIT_SOURCE" >&2
  exit 1
fi
cp "$WIT_SOURCE"/*.wit "$STAGE/deps/pumpkin-plugin/"

cargo run --release -p wit_bindgen_dart --bin witgen_cli -- \
  --input "$STAGE" \
  --world plugin \
  --output packages/pumpkin_api/lib/src/bindings.g.dart \
  --abi-output packages/pumpkin_api/hook/wasm_abi.json

# The bindings are written by now, so a missing `dart` must not fail the script
# (that would report a successful generation as a failure). It must not pass
# silently either: skipping this step leaves `events.g.dart` stale against the
# bindings just written, which only shows up later as a confusing mismatch in a
# port. On this machine `dart` is off PATH outside a `puro` shell, so the
# warning is the normal case rather than an accident. The guard also keeps
# `set -e` from aborting on `command not found` before the warning is printed.
if command -v dart >/dev/null 2>&1; then
  dart run tool/generate_events.dart
else
  echo "WARNING: 'dart' is not on PATH, so events.g.dart was NOT regenerated." >&2
  echo "         The WIT bindings above are written; run the events step yourself:" >&2
  echo "           puro dart run tool/generate_events.dart" >&2
fi
