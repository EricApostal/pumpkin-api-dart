# Events, time and the plugin context

## Listening

```dart
final sub = context.listen(Events.playerJoin, (server, event) {
  logger.info('${event.player.getName()} joined');
});
sub.cancel();                       // stop listening
```

`listen` observes, `intercept` changes or cancels the event (the server waits for
it). Events with a `cancelled` field have a generated `cancel()`:

```dart
context.intercept(Events.playerChat, (server, event) => event.cancel());
```

The server can't unregister a handler, so `cancel()` makes it inert: it stays
registered but is ignored.

`context.once(kind, handler, where: ...)` runs for the first matching event only.

## Waiting for an event

```dart
sender.reply('Type your answer in chat.');
final chat = await context.next(
  Events.playerChat,
  where: (chat) => chat.player.getName() == name,
  timeout: const Duration(seconds: 30),
);   // throws TimeoutException if nobody answers
```

The event's resources (like its `player`) are valid until your code first awaits
again, so read what you need right away.

## `Plugin.context`

The `context` parameter of `onLoad` is only valid while it runs. `Plugin.context`
is the same context, kept for as long as the plugin is loaded, so command handlers
and other later callbacks can register events and use `next`.

## Time

The server runs 20 ticks per second. Prefer durations:

```dart
server.after(const Duration(seconds: 5), (server) => ...);
final task = server.every(const Duration(minutes: 1), (server) => ...);
task.cancel();
```

Durations round up to whole ticks (50ms). `20.ticks` is a one second `Duration`.
`Debouncer` and `Throttle` smooth out bursts of calls.

## Enum names

Every enum has `wireName` (its name in the WIT, like `iron-golem`) and
`fromWireName`:

```dart
EntityType.ironGolem.wireName;          // 'iron-golem'
EntityType.fromWireName('iron-golem');  // EntityType.ironGolem
```
