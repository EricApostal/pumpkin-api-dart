# Plugin infrastructure

Helpers for cleanup, logging, plugin-to-plugin messages, client mod channels
and permission nodes. Everything is plain Dart on top of the generated API.

## Unload hooks and disposables (`lifecycle.dart`)

```dart
context.onUnload(timer.cancel);
context.onUnload(() async => await flush());   // see the caveat below

final bag = DisposableBag()..disposeOnUnload();
bag.addTimer(Timer.periodic(Duration(seconds: 30), (_) => save()));
final sub = bag.addCallback(() => logger.info('bye'));
sub.cancel();                                   // removes it without running
```

Hooks and bags run newest first. Every cleanup is guarded: a failure is logged
and the rest still run. `Subscription` is the handle for anything cancellable
(`cancel()`, `isCancelled`); it is also a `Disposable`.

The dispatcher must call `runUnloadHooks()` from its `onUnload` export. It
returns a `Future` only if some hook is async. The host does not wait for work
after the first `await` (see async.md), so keep unload hooks synchronous.

## Loggers (`logger.dart`)

```dart
final log = Logger('teleport');             // "[teleport] ..."
log.info('saved');
log.debug(() => 'state: ${dump()}');         // closure only runs if enabled
log.error('save failed', error: e, stackTrace: s);
log.minLevel = Level.warn;                   // per logger; the global logger sets the default
final n = log.time('load', () => loadAll()); // debug: "load took 12ms"; awaits Futures
```

`logger` (global) and `Logger.trace/debug/info/warn/error` work as before.
`log.child('db')` prefixes `[teleport.db]`.

## Typed IPC (`ipc.dart`)

The host call is synchronous: the recipient runs before the call returns.

```dart
final reply = ipc.requestJson('economy', {'op': 'balance'});   // decoded JSON
ipc.sendJson('economy', {'op': 'ping'});                       // reply ignored
final bytes = ipc.request('economy', utf8.encode('raw'));      // raw bytes
```

Failures throw `IpcException` with a `reason`: `pluginNotFound`, `rejected`
(the recipient threw; the message is its error text) or `badPayload`.

Typed channels wrap messages in a `{"type": name, "data": ...}` envelope:

```dart
final transfer = IpcChannel<Transfer>('economy.transfer', encodeTransfer, decodeTransfer);
transfer.handle((sender, t) => {'ok': bank.move(t)});   // receiver, returns JSON reply
final r = transfer.request('economy', Transfer(...));    // sender
```

Handlers live in `ipcHandlers`. Incoming messages must reach `handleIpc`:
make `Plugin.onMessage` call `handleIpc(sender, bytes)` by default.
`ipcHandlers.fallback` receives anything that is not a handled envelope.
A plugin cannot message itself (the host reports it as not available).

## Custom payload channels (`channels.dart`)

```dart
final channel = PluginChannel('myplugin:main');
channel.listen(context, (player, data) => channel.sendString(player, 'pong'));
channel.registeredPlayers;   // List<ChannelPlayer(uuid, name)>, plain data
```

Only Java players receive payloads (`send` throws `UnsupportedError` for
Bedrock). `registeredPlayers` is built from the register, unregister and leave
events seen after `listen`.

## Permission nodes (`permission_nodes.dart`)

```dart
const home = PermissionNode('teleport:command.home',
    description: 'Use /home', defaultValue: PermissionDefaultKind.allow);
context.registerPermissions([home]);     // returns how many were new
if (player.can(home)) { ... }            // Player.hasPermission
if (sender.can(server, home)) { ... }    // CommandSender.hasPermission
```

Defaults: `PermissionDefaultKind.allow`, `.deny`, `const PermissionDefaultKind.op(level)`.
`children` takes the generated `PermissionChild(node:, value:)`.
