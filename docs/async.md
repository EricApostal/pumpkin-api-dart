# Async code

Pumpkin's plugin API is asynchronous: every host function that has to run on the
server's own threads (changing a world, moving or healing a player, reading or
changing an item stack, checking a permission, ...) is an `async func` in the
WIT, and the generated Dart function returns a `Future`. A plugin awaits them.

```dart
Future<int> heal(CommandSender sender, Server server, ConsumedArgs args) async {
  final player = sender.asPlayer()!;
  if (!await player.hasPermission(node: 'myplugin:heal')) {
    throw CommandException("You can't do that.");
  }
  await player.heal(amount: 20);
  return 1;
}
```

Calls that only read cheap state (`player.getName()`, `player.getPosition()`,
`server.getAllPlayers()`, ...) are still plain synchronous calls.

## How a call runs

A call to an async host function does not block the plugin. It starts the call
and returns the future; the plugin keeps running until it awaits the result. The
component model runs each callback from the server as a *task*, and the task
stays alive until every host call it started has finished. Several callbacks can
be suspended at the same time while the server keeps running.

* `await` on a host call lets the server continue with other work, and wakes the
  callback when the call is done.
* A call you do not await still runs (the callback does not end before it has
  finished), but you cannot observe its failure or order. Wrap it in
  `unawaited(...)` when that is what you want. The repository's lint rules flag
  forgotten awaits (`unawaited_futures`).
* Anything that holds a host resource (`player`, `server`, an `ItemStack`, ...)
  must be awaited before the resource is disposed.

## Timers and your own futures

Standalone `dart2wasm` has no event loop, so `pumpkin_api` provides one on top of
the server's tick scheduler:

* microtasks run before the callback returns to the server or waits for the
  host, so awaiting completed futures costs nothing,
* timers (`Future.delayed`, `Timer`, `Timer.periodic`) fire on the server's tick
  loop (20 ticks per second, so a resolution of 50ms; shorter durations round up
  to one tick, a zero duration runs right after the current microtasks),
* an `async` function resumes in a later tick when it waits for a timer.

```dart
Future<int> countdown(CommandSender sender, Server server, ConsumedArgs args) async {
  sender.reply('Starting...');
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

The server waits for a callback while it has host calls to wait for. Once all
that is left is a timer, or a future that another callback completes, it gets a
fallback result and the rest of your code carries on in a later tick (failures
are logged):

| Callback | Result when it waits for a timer or another callback |
| --- | --- |
| `onLoad`, `onUnload` | success, loading continues |
| command handler | success (`1`) |
| `listen` / `intercept` handler | the event unchanged |
| suggestion handler | no suggestions |
| `onMessage` (IPC) | an empty reply |
| AI goal, chunk generator | `false` / nothing |

So awaiting host calls is fine in every handler, even in `intercept` handlers
that change the event or command handlers whose result is used. Awaiting a timer
there means the server will not see what happens afterwards.

Objects the server hands to a callback (`server`, `sender`, `context`, an
event's `player`) stay valid for as long as the callback waits for host calls.
After it has waited for a timer they are gone (use `keep()` on owned ones, or
store the UUID), see [lifetimes](lifetimes.md).

Uncaught errors from async code are logged as `Uncaught error in ...` and
never crash the plugin.

## How it works

`wasm_components` implements the callback ABI of the component model's async
support. Each async import is lowered with the `async` option, the generated
code gets a status word and a subtask handle back, and awaiting it adds the
subtask to the callback's waitable set. The server calls the plugin's `callback`
export when a subtask has finished, which completes the future. See
`packages/wasm_components/lib/src/runtime/async/task.dart`, and
`native/wit_bindgen_dart` for the generator (it uses a patched
`wit-bindgen-core` in `native/vendor`, because the upstream one cannot lower
async imports yet).
