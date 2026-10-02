# Async code

Plugin callbacks can use `async`/`await`, `Future.delayed`, `Timer` and
`Timer.periodic`. Standalone `dart2wasm` has no event loop, so `pumpkin_api`
provides one on top of the server's tick scheduler:

* microtasks run before the callback returns to the server, so awaiting
  completed futures costs nothing,
* timers fire on the server's tick loop (20 ticks per second, so a resolution of
  50ms; shorter durations round up to one tick, a zero duration runs right
  after the current microtasks),
* an `async` function resumes in a later tick when it waits for a timer.

```dart
Future<int> countdown(CommandSender sender, Server server, ConsumedArgs args) async {
  sender.reply('Starting...');                 // before the first await
  for (var i = 3; i > 0; i--) {
    logger.info('$i...');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return 1;
}
```

Use `20.ticks` as a readable duration, and `Server.runLater`/`runRepeating` for
callbacks that need a `Server`.

## What the server waits for

The server calls plugins synchronously, so it can only use what a callback
produces before it first returns:

| Callback | If it is still running after its first `await` |
| --- | --- |
| `onLoad`, `onUnload` | loading continues, later errors are logged |
| command handler | the command reports success (`1`), later errors are logged |
| `listen` event handler | nothing to report, later errors are logged |
| `intercept` handler | must be synchronous: the server needs the event back |
| suggestion handler | no suggestions are returned |

`server`, `sender` and `context` are only valid until the first `await`. Owned
resources (like an event's `player`) stay valid until the async work finishes,
see [lifetimes](lifetimes.md).

Uncaught errors from async code are logged as `Uncaught error in ...` and
never crash the plugin.
