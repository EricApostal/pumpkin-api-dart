# How it fits together

```
 your plugin (Dart)
        │  package:pumpkin_api   -- wrappers: Plugin, events, commands, tasks, ...
        │  bindings.g.dart       -- generated from wit/ by native/wit_bindgen_dart
        ▼
 dart2wasm --standalone          -- Dart to a core Wasm module with `dart:*` host imports
        ▼
 wasm_tools (pumpkin build)      -- links the Dart host imports against wasm_components,
        │                           links runtime_helpers.wasm, and wraps the result as a
        │                           Wasm component implementing the `plugin` world
        ▼
 plugin.wasm  ──►  Pumpkin (Wasmtime)
```

* **`wit/`**: the interface Pumpkin exposes to plugins, a submodule of
  `pumpkin-plugin-wit`.
* **`wit-dart/`**: the world the bindings are generated from: Pumpkin's `plugin`
  world plus WASI imports (files), with the WASI WIT vendored in `deps/`.
* **`native/wit_bindgen_dart`**: reads the WIT and generates the Dart bindings
  plus a JSON description of the ABI (`hook/wasm_abi.json`) that the compiler
  needs to build the component. Only maintainers run it.
* **`packages/pumpkin_api`**: the generated bindings and the hand-written API on
  top. A build hook registers the ABI, so plugin authors only depend on this
  package.
* **`packages/wasm_tools`**: the compiler. `pumpkin build` calls it.
* **`packages/wasm_components`**: the Dart runtime: the standalone embedder
  (strings, math, clocks), resource ownership (`Resource`, `ResourceScope`) and
  component async support.
* **`native/runtime_helpers`**: a small Rust allocator and math library compiled
  to Wasm and linked into every plugin. The compiled module is checked in.

## Regenerating

```sh
git submodule update --remote wit
tool/generate_bindings.sh        # bindings, ABI and the typed `Events`
tool/build_runtime_helpers.sh    # only if native/runtime_helpers changed
```

## Testing a plugin against a server

`tool/smoke_test.sh` loads a plugin into a throwaway Pumpkin server on spare
ports, types console commands into it and prints the log:

```sh
PUMPKIN_BIN=/path/to/pumpkin tool/smoke_test.sh build/my_plugin.wasm "mycommand arg"
```

Use a release build of Pumpkin: compiling a plugin on first load is far slower in
debug builds.
