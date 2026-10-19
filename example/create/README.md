# create

The server side of the [Create](https://github.com/Creators-of-Create/Create)
mod as a Pumpkin plugin written in Dart (dart2wasm component). This package is the
**foundation**: the module system, registry, block entity framework with batched
ticking, payload networking, config, saved data and the NeoForge declaration. The
game content lives in modules under `lib/src/<module>/`.

Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```sh
export PATH=$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin:$PATH
dart run build_runner build      # regenerate *.mapper.dart after editing models
dart test                        # VM tests of the pure parts
dart analyze
dart run pumpkin_tools build     # build/create.wasm
wasm-tools validate --features all build/create.wasm
```

Set `"core": {"debug_smoke_test": true}` in the plugin's `config.json` to register
`create:smoke_block`, a framework smoke test (block entity that ticks and persists a
counter). `"core": {"neoforge": true}` declares the mod to the host's NeoForge
handshake.
