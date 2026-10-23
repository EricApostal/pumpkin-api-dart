#!/bin/sh
# Builds `jolt.wasm`: Jolt Physics 5.6.1 as a freestanding wasm32-wasip1 core
# module with the C ABI in `src/jolt_abi.cpp`.
#
# Requirements: a wasi-sdk 34 checkout and a Jolt 5.6.1 source tree. Neither is
# vendored (Jolt is ~30 MB of C++), so point the script at them:
#
#   JOLT_SRC=/path/to/JoltPhysics WASI_SDK=/path/to/wasi-sdk-34.0-x86_64-linux \
#     ./build.sh
#
# The three patches in `patches/` are applied to JOLT_SRC if they are not
# already in place (they are the ones recorded in `/tmp/joltspike/ADR.md` §3).
#
# The resulting module has **no imports**, exports `memory` and `_initialize`,
# and is checked in next to this script so building the plugin does not need a
# C++ toolchain.
set -eu
cd "$(dirname "$0")"

JOLT_SRC="${JOLT_SRC:-$PWD/JoltPhysics}"
WASI_SDK="${WASI_SDK:-$PWD/toolchain/wasi-sdk-34.0-x86_64-linux}"

if [ ! -d "$JOLT_SRC/Jolt" ]; then
  echo "JOLT_SRC does not point at a Jolt checkout: $JOLT_SRC" >&2
  exit 1
fi
if [ ! -x "$WASI_SDK/bin/clang++" ]; then
  echo "WASI_SDK does not point at a wasi-sdk: $WASI_SDK" >&2
  exit 1
fi

if ! grep -q '__wasi__' "$JOLT_SRC/Jolt/Core/Core.h"; then
  for patch in patches/*.patch; do
    echo "applying $patch"
    patch -p1 -d "$JOLT_SRC" < "$patch"
  done
fi

CXX="$WASI_SDK/bin/clang++"
SYSROOT="$WASI_SDK/share/wasi-sysroot"
FLAGS="--target=wasm32-wasip1 --sysroot=$SYSROOT -std=c++17 -O2 -fno-exceptions -fno-rtti -I$JOLT_SRC"

# Excluded, per ADR §3: the thread pool, the barrier it needs, its semaphore and
# the iostream-based state recorder.
EXCLUDE='JobSystemThreadPool\.cpp|JobSystemWithBarrier\.cpp|Semaphore\.cpp|StateRecorderImpl\.cpp'

mkdir -p build/obj
find "$JOLT_SRC/Jolt" -name '*.cpp' | grep -Ev "$EXCLUDE" | sort > build/sources.txt
echo "compiling $(wc -l < build/sources.txt) Jolt translation units"

compile_one() {
  src="$1"
  obj="build/obj/$(echo "${src#$JOLT_SRC/}" | tr '/' '_').o"
  if [ -f "$obj" ] && [ "$obj" -nt "$src" ]; then
    return 0
  fi
  $CXX $FLAGS -c "$src" -o "$obj"
}

MAX_JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
running=0
while read -r src; do
  compile_one "$src" &
  running=$((running + 1))
  if [ "$running" -ge "$MAX_JOBS" ]; then
    wait
    running=0
  fi
done < build/sources.txt
wait

$CXX $FLAGS -c src/jolt_abi.cpp -o build/obj/jolt_abi.cpp.o

OBJS=$(ls build/obj/*.o)
# A reactor: `_initialize` instead of `_start`, memory exported, no entry point.
$CXX $FLAGS -mexec-model=reactor -Wl,--no-entry -Wl,--gc-sections \
  -Wl,-z,stack-size=1048576 -Wl,--initial-memory=33554432 -Wl,--export-memory \
  $OBJS -o jolt.wasm

ls -la jolt.wasm
