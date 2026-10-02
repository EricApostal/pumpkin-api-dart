#!/bin/sh
# Regenerates the Dart bindings in packages/pumpkin_api from the WIT: Pumpkin's
# plugin world (the `wit` submodule) plus the WASI imports in `wit-dart`.
# Usage: tool/generate_bindings.sh [wit-version]   (default: v0.2)
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-v0.2}"

# Stage the world together with Pumpkin's WIT as a dependency.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R wit-dart/. "$STAGE/"
mkdir -p "$STAGE/deps/pumpkin-plugin"
cp "wit/$VERSION"/*.wit "$STAGE/deps/pumpkin-plugin/"

cargo run --release -p wit_bindgen_dart --bin witgen_cli -- \
  --input "$STAGE" \
  --world plugin \
  --output packages/pumpkin_api/lib/src/bindings.g.dart \
  --abi-output packages/pumpkin_api/hook/wasm_abi.json

dart run tool/generate_events.dart
