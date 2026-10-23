# pumpkin-api-dart

Write [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin) plugins in Dart.

Plugins are compiled with `dart2wasm --standalone` and packaged as
[WebAssembly components](https://component-model.bytecodealliance.org/) that
implement the `plugin` world from
[pumpkin-plugin-wit](https://github.com/Pumpkin-MC/pumpkin-plugin-wit).

> [!NOTE]
> This does not work with pumpkin master. If you want to use this in your
> own project, you'll need to fork it and generate the bindings against
> pumpkin master.

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

`package:pumpkin_api` wraps the generated WIT bindings in an API that feels like
Dart. Extend `Plugin`, register what you need in `onLoad`, and call `runPlugin`:

```dart
import 'package:pumpkin_api/pumpkin_api.dart';

void main() => runPlugin(MyPlugin());

final class MyPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(name: 'my_plugin', version: '0.1.0');

  @override
  void onLoad(Context context) {
    // Events are typed. `listen` observes, `intercept` can change or cancel.
    context.listen(Events.playerJoin, (server, event) {
      logger.info('${event.player.getName()} joined');
    });
    context.intercept(Events.playerChat, (server, event) {
      return event.copyWith(message: event.message.toUpperCase());
    });

    // Commands take closures. Throw a `CommandException` to fail a command.
    final shout = CommandNode.argument(
      name: 'text',
      type: ArgumentTypes.greedyString,
    )..execute((sender, server, args) {
        sender.reply(args.string('text').toUpperCase());
        return 1;
      });
    context.registerCommand(
      command: Command.create(names: ['shout'], description: 'Shouts')
        ..then(node: shout),
      permission: 'my_plugin:shout',
    );

    // Tasks take closures too (20 ticks per second).
    context.runLater(100, (server) => logger.info('Five seconds in'));
  }
}
```

## Working on this repository

```sh
git clone --recurse-submodules <this repo>
dart pub get
cd example/teleport && dart run pumpkin_tools build
```

### Core modules

A plugin that needs a pre-compiled core module — C or C++ compiled to Wasm, checked in next to the source that builds it, so a build needs no toolchain — declares it in its **own** `pubspec.yaml`:

```yaml
pumpkin:
  core_modules:
    - name: jolt
      path: native/jolt/jolt.wasm
```

`name` is the module Dart imports from (`@pragma('wasm:import', 'jolt.jolt_alloc')`, plus `jolt.memory` as a `Memory`), and `path` is relative to the package root. `pumpkin_tools build` links it into that package's component only.

This must not be a `hook/build.dart`: a build hook of package A also runs while any package that depends on A is built, which links A's module into the dependents' components, where nothing imports it and the link fails with `Expected compiled app to export {host_call}`. `example/sable` (Jolt) and `example/cc_tweaked` (Lua) declare their modules this way.

Regenerate the bindings and the typed `Events` after the WIT changes (needs Rust):

```sh
git submodule update --remote wit
tool/generate_bindings.sh v0.2
```

To generate from WIT that is not in the submodule yet (say a branch of the
Pumpkin repository), point `WIT_DIR` at the directory with the version's `.wit`
files; it replaces `wit/<version>`:

```sh
WIT_DIR=~/src/Pumpkin/crates/pumpkin-plugin-wit/v0.2 tool/generate_bindings.sh v0.2
```

`tool/build_runtime_helpers.sh` rebuilds `runtime_helpers.wasm` and needs
nightly Rust with `wasm32-unknown-unknown` and `rust-src`.

## License

The code derived from [wasm.dart](https://github.com/simolus3/wasm.dart)
(`packages/wasm_tools`, `packages/wasm_components`, `native/`) is under the
BSD-style license in [LICENSE](LICENSE), copyright Simon Binder. The license
for the rest of this repository hasn't been chosen yet.
