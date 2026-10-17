#!/bin/sh
# Spike: builds Lua 5.2 for wasm32-wasip1 with wasm exception based setjmp/longjmp.
set -e
cd "$(dirname "$0")/.."
W="$(cd ../toolchain/wasi-sdk-34.0-arm64-macos && pwd)"
CC="$W/bin/clang --target=wasm32-wasip1 --sysroot=$W/share/wasi-sysroot"
FLAGS="-O2 -mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false -DLUA_USE_POSIX"
SRC=$(ls lua-5.2.4/*.c | grep -v -E '/(lua|luac)\.c$')
$CC $FLAGS -Ilua-5.2.4 $SRC spike/bench.c -o spike/bench.wasm -lsetjmp
ls -la spike/bench.wasm
