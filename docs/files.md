# Files

Plugins keep files that survive restarts in their own data folder, with
`context.files` (a `DataFolder`):

```dart
final class MyPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'my_plugin',
    version: '1.0.0',
    permissions: [Permissions.fsWriteData], // fsReadData for read-only access
  );

  @override
  void onLoad(Context context) {
    final data = context.files;
    data.createDirectory('homes');
    data.writeJson('homes/steve.json', {'x': 10, 'y': 64, 'z': -3});
    final home = data.readJson('homes/steve.json');
  }
}
```

`DataFolder` has `readAsString`/`readAsBytes`/`readJson`, `writeAsString`/
`writeAsBytes`/`writeJson` (with `append: true`), `exists`, `stat`, `list`,
`createDirectory` and `delete` (`recursive: true` for directories). Paths are
relative to the folder and use `/`; `..` is rejected. Failures throw
`FileException` (`isNotFound`, `alreadyExists`, `isAccessDenied`).

* The folder only exists if the plugin requests `fs.read.data` or `fs.write.data`,
  and the server operator approves it (or pre-approves it in the `[plugins]`
  config). Without it, using `files` throws a `StateError` that says so.
* Files live under `plugins/data/<plugin name>/` on the server.
* Calls are synchronous: the server tick waits for the disk. Keep reads and
  writes small and infrequent in hot paths.
* `DataFolder` holds no handles, so it's safe to keep in a field.

## Why WASI 0.2

This uses `wasi:filesystem@0.2.12`. WASI 0.3 replaces file reads and writes with
`stream<u8>` and `future<...>` handles, and Wasmtime only lets an *async* task
wait on those. Every export of the plugin world (`on-load`, `handle-command`, ...)
is a plain synchronous function, so a 0.3 read from one of them traps. Moving to
0.3 would need the plugin's exports to be lifted as async tasks, a finished Dart
event loop and stream/future support in the compiler and generator. `DataFolder`
hides the WASI version, so plugins won't change when that happens.

The WASI interfaces come from `wit-dart/` (vendored, with a world that includes
Pumpkin's `plugin` world), and the raw bindings stay hidden from the public API.
