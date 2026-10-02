# wit-dart

The WIT this repository generates its bindings from: a world that includes
Pumpkin's `plugin` world (`../wit`) and adds WASI imports for plugins.

`deps/` holds vendored WASI 0.2.12 packages (from `wasmtime-wasi`). Pumpkin's
own WIT is copied next to them by `tool/generate_bindings.sh` before generating.
