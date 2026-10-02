# pumpkin-api-dart

Write [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin) plugins in Dart.

Plugins are compiled with `dart2wasm --standalone` and packaged as
[WebAssembly components](https://component-model.bytecodealliance.org/) that
implement the `plugin` world from
[pumpkin-plugin-wit](https://github.com/Pumpkin-MC/pumpkin-plugin-wit).

> [!NOTE]
> Experimental. Plugins need Dart 3.14 or newer (the dev channel, or the Dart
> bundled with Flutter master, e.g. `puro use master`). Older SDKs emit Wasm
> exception instructions that Pumpkin's runtime rejects.

## Quick start

Install the CLI, then create and build a plugin:

```sh
dart pub global activate --source git https://github.com/EricApostal/pumpkin-api-dart \
  --git-path packages/pumpkin_tools

pumpkin new my_plugin
cd my_plugin
dart pub get
pumpkin build
```

Copy `build/my_plugin.wasm` into your server's `plugins/` directory. You don't
need Rust: the bindings and the runtime helper module are checked in.

## Writing a plugin

Extend `Plugin` and override only the callbacks you need. The WIT world
requires every component to export all host callbacks, so `Plugin` provides a
default for each one.

```dart
import 'package:pumpkin_api/pumpkin_api.dart';

void main() => runPlugin(MyPlugin());

final class MyPlugin extends Plugin {
  @override
  PluginMetadata get metadata => const PluginMetadata(
    name: 'my_plugin',
    version: '0.1.0',
    authors: [],
    description: 'My first plugin.',
    dependencies: [],
    permissions: [],
  );

  @override
  Result<void, String> onLoad(Context context) {
    logging.log(level: Level.info, message: 'Hello from Dart!');
    return const Result.ok(null);
  }
}
```

See [`example/hello_plugin`](example/hello_plugin) for commands, permissions and
scheduled tasks.

## Repository layout

| Path | Contents |
| --- | --- |
| `wit/` | Git submodule: `pumpkin-plugin-wit` (`v0.1`, `v0.2`). |
| `packages/pumpkin_api` | The plugin API: generated bindings plus the `Plugin` base class. |
| `packages/pumpkin_tools` | The `pumpkin` CLI (`new`, `build`). |
| `packages/wasm_tools` | Compiler from Dart programs to components (fork of [wasm.dart](https://github.com/simolus3/wasm.dart)). |
| `packages/wasm_components` | Runtime support for components in Dart. |
| `native/wit_bindgen_dart` | Rust WIT-to-Dart binding generator (maintainers only). |
| `native/runtime_helpers` | Rust allocator and math helpers linked into every plugin (maintainers only). |
| `example/hello_plugin` | Example plugin. |

## Working on this repository

```sh
git clone --recurse-submodules <this repo>
dart pub get
cd example/hello_plugin && dart run pumpkin_tools build
```

Regenerate the bindings after the WIT changes (needs Rust):

```sh
git submodule update --remote wit
tool/generate_bindings.sh v0.2
```

`tool/build_runtime_helpers.sh` rebuilds `runtime_helpers.wasm` and needs
nightly Rust with `wasm32-unknown-unknown` and `rust-src`.

## License

The code derived from [wasm.dart](https://github.com/simolus3/wasm.dart)
(`packages/wasm_tools`, `packages/wasm_components`, `native/`) is under the
BSD-style license in [LICENSE](LICENSE), copyright Simon Binder. The license
for the rest of this repository hasn't been chosen yet.
