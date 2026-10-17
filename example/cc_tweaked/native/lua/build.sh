#!/bin/sh
# Builds src/cc_lua.c and the vendored Lua 5.2 into lua.wasm (a core module).
set -e
cd "$(dirname "$0")"
W="$(cd ../toolchain/wasi-sdk-34.0-arm64-macos && pwd)"
CC="$W/bin/clang --target=wasm32-wasip1 --sysroot=$W/share/wasi-sysroot"
FLAGS="-O2 -Isrc -DCC_WASM -DLUA_COMPAT_ALL -Dluai_makeseed()=0x5eed1234u -mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false"
# The prelude becomes a C string literal.
sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/\\n"/' src/prelude.lua > src/prelude.inc
EXPORTS=$(sed 's/.*/-Wl,--export=&/' exports.txt | tr '\n' ' ')
SRC=$(ls lua-5.2.4/*.c | grep -v -E '/(lua|luac|liolib|loslib|loadlib|linit)\.c$')
$CC $FLAGS -Ilua-5.2.4 $SRC src/cc_lua.c src/lutf8lib.c src/selftest.c -o lua.wasm -mexec-model=reactor \
  -Wl,--no-entry -Wl,--gc-sections -Wl,-z,stack-size=524288 -Wl,--initial-memory=4194304 \
  $EXPORTS -lsetjmp
ls -la lua.wasm
