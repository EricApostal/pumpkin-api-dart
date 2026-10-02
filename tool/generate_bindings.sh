#!/bin/sh
# Regenerates the Dart bindings in packages/pumpkin_api from the WIT submodule.
# Usage: tool/generate_bindings.sh [wit-version]   (default: v0.2)
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-v0.2}"

cargo run --release -p wit_bindgen_dart --bin witgen_cli -- \
  --input "wit/$VERSION" \
  --world plugin \
  --output packages/pumpkin_api/lib/src/bindings.g.dart \
  --abi-output packages/pumpkin_api/hook/wasm_abi.json
