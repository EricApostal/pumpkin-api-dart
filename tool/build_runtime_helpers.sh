#!/bin/sh
# Rebuilds packages/wasm_tools/assets/runtime_helpers.wasm. Needs nightly Rust
# with the wasm32-unknown-unknown target and rust-src. Run from the repo root.
set -e
cd "$(dirname "$0")/.."

RUSTFLAGS="-Zlocation-detail=none -Zfmt-debug=none -Zunstable-options -Cpanic=immediate-abort" \
  cargo +nightly build --release \
    -Zbuild-std=core,alloc,panic_abort \
    -Zbuild-std-features= \
    --target wasm32-unknown-unknown \
    -p runtime_helpers

cp target/wasm32-unknown-unknown/release/runtime_helpers.wasm packages/wasm_tools/assets/
