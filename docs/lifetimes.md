# Resource lifetimes

Most of the host API is made of *resources*: `Player`, `World`, `Entity`,
`Server`, `TextComponent`, `Command` and so on. The server keeps the real object
in a table and gives the plugin an integer handle. A handle that is never
released keeps its object alive in that table forever, so plugins must release
them.

Dart has no destructors, and standalone `dart2wasm` has no finalizers, so
`pumpkin_api` tracks handles for you with **scopes**.

## The rule

> A resource you receive from the server is valid until the callback that
> received it returns.

Every call from the server into your plugin (`onLoad`, an event handler, a
command, a task, ...) opens a scope. When the callback returns, everything that
was received during it is released:

* handles you **own** (returned by a host function, or an event's `player`) are
  dropped, so the server can free the object,
* handles the server only **lends** (the `server` and `sender` parameters, the
  `context` of `onLoad`) are invalidated.

Using a resource after that throws a `StateError` instead of corrupting the
server's table:

```dart
Player? last;

context.listen(Events.playerJoin, (server, event) {
  last = event.player;                 // fine, but...
});

context.runLater(100, (server) {
  last!.getName();                     // StateError: no longer valid
});
```

## Keeping a resource

Call `keep()` on a resource **returned by a host function** to hold on to it, and
`dispose()` when you are done with it:

```dart
final world = server.getWorldByName(name: 'world')!.keep();
// ... later
world.dispose();
```

The resources an **event** carries (`event.player`, `event.targetWorld`, ...) are
released by the server as soon as the callback returns, whether or not you called
`keep()`; the host deletes them from its table unconditionally. Storing one only
gives you a dead handle, so look the object up again through a host function
when you need it later:

```dart
String? lastWorldId;

context.listen(Events.worldTick, (server, event) {
  lastWorldId = event.targetWorld.getId();
});

context.runLater(100, (server) {
  final world = server.getWorldByName(name: lastWorldId!);   // fresh handle
});
```

`keep()` does not merely fail to help there: when the plugin hands the event back
the host takes ownership of its handles, so the wrapper you stored is invalidated
(`StateError: ... ownership was transferred to the host`) on top of the entry being
gone. A list of online players is the shape this trap usually takes — store the
uuid of the event's player and look the player up again for each send:

```dart
final roster = <String, Player>{};

context.listen(Events.playerJoin, (server, event) {
  final id = event.player.getId();                       // read it here; the handle dies after
  final player = server.getPlayerByUuid(id: id);         // a handle this plugin owns
  if (player != null) roster[id.asString] = player.keep();
});
```

Borrowed resources (`server`, `sender`, `context`) can't be kept, because the
server only lends them for the duration of the call. Look the object up again
when you need it, or use the scheduler APIs that hand you a fresh `server`.

## Per-world adapters

A cached object that wraps a world — a level view, a physics adapter, a
per-world runtime — is the place this rule is easiest to break: the cache is
keyed by world id, but the object it stores is built from the *first* world
handle it saw, and that handle usually came from an event. The next event then
finds the cached object and uses a handle that was released a tick ago:

```dart
// Wrong: the first caller's handle is cached forever.
final _adapters = <String, Adapter>{};
Adapter adapterOf(World world) =>
    _adapters.putIfAbsent(world.getId(), () => Adapter(world));
```

Create's `WorldRef` (in `package:create`, `src/core/worlds.dart`) stores the id
and the last handle that was still valid. Bind it in the callback that has a
live world; after that it resolves the id through the plugin's kept `Worlds`
table, whose entries do outlive callbacks:

```dart
final _adapters = <String, Adapter>{};

Adapter adapterOf(World world) {
  final adapter = _adapters[world.getId()] ??= Adapter(WorldRef(worlds, world.getId()));
  adapter.ref.bind(world);   // no host call: just remembers the live handle
  return adapter;
}

// Later, from any callback or timer:
adapter.ref.world.getBlockStateId(pos: pos);
```

`WorldRef.world` returns the bound handle while it is valid, so a tick that
already has one costs no host call; once it is gone it asks `Worlds` for a kept
one, which is a map lookup on the common path and a `Server.getWorldByName`
only after the world unloaded.

## Giving a resource away

Some host functions take ownership of an argument, for instance
`Context.registerCommand(command: ...)` takes the `Command`. The Dart object is
consumed by the call: don't use it afterwards. You also don't have to dispose of
it.

## In async code

A scope stays open while the work a callback started is still running (its
returned `Future`, pending `Timer`s), so owned resources remain usable across
`await`s. Borrowed ones (`server`, `sender`, `context`) are lent for as long as
the callback waits for host calls; once it has waited for a timer or a future
that another callback completes, the server has been given a result and stops
lending them. Use them before such a wait (see [async.md](async.md)).
