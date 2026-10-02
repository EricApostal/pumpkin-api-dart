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

Call `keep()` on an owned resource to hold on to it, and `dispose()` when you
are done with it:

```dart
Player? last;

context.listen(Events.playerJoin, (server, event) {
  last?.dispose();
  last = event.player.keep();
});
```

Borrowed resources (`server`, `sender`, `context`) can't be kept, because the
server only lends them for the duration of the call. Look the object up again
when you need it, or use the scheduler APIs that hand you a fresh `server`.

## Giving a resource away

Some host functions take ownership of an argument, for instance
`Context.registerCommand(command: ...)` takes the `Command`. The Dart object is
consumed by the call: don't use it afterwards. You also don't have to dispose of
it.

## In async code

A scope stays open while the work a callback started is still running (its
returned `Future`, pending `Timer`s), so owned resources remain usable across
`await`s. Borrowed ones don't: the server stops lending them as soon as the
callback first returns to it. Use them before the first `await`.
