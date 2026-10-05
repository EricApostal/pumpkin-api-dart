# Connection phases: custom handshakes

Hooks for the *login* and *configuration* phases of a connection, the two
phases before a player joins the world. A plugin can take part in them, which is
what a mod loader's handshake needs; Pumpkin only provides the primitives
(events, raw packets, holds), the protocol is plugin code. This page is the user
guide; the design is in [configuration-hook.md](configuration-hook.md), and
[loader-notes.md](loader-notes.md) has what NeoForge clients expect.

Mods with their own client side (Fabric, Forge, NeoForge, ...) usually talk to
the server **before the player joins**, in the *configuration* phase: after
login, before the world is sent. Pumpkin reports that phase to plugins, so a
plugin can check that the client has its mod, exchange settings, and only then
let the player in. The design is in [configuration-hook.md](configuration-hook.md);
this page is the user guide.

```text
LOGIN ───────────► CONFIGURATION ───────────────────────────────────────────► play
 login start       pre-brand (hold)    start (hold)      ... registries ...
 (hold)            BEFORE the brand    after the brand   finish (hold)    end
 queries/answers   payloads, packets,  payloads, packets payloads, packets
 release           flavour; release    release           release
 onLogin           onConfiguration     onConfiguration   onConfiguration
                   (onPreBrand:)       (handler)         (onFinish:)
```

* `onLogin`: login queries (the login phase has no custom payloads).
* `onConfiguration`: custom payloads and raw packets, with a hold at the start,
  a second one right before "finish configuration" and, if you ask for it, an
  earlier one before the server's brand (the *pre-brand* stage).

## A handshake in a few lines

```dart
const hello = 'mymod:hello';
const ack = 'mymod:ack';

@override
void onLoad(Context context) {
  context.onConfiguration((connection) async {
    connection.send(hello, PayloadCodecs.string.encode('Welcome ${connection.username}!'));

    final reply = await connection.next(ack, timeout: const Duration(seconds: 5));
    if (reply == null) {
      connection.disconnect('This server needs the My Mod client mod.');
      return;
    }
    logger.info('${connection.username} runs ${connection.brand}');
    connection.release();   // let the client continue
  });
}
```

`onConfiguration` runs the handler once for every client that enters the phase.
The handler is a normal `async` function, so the handshake reads top to bottom.

* The server **holds** the configuration while the handler runs (by default for
  at most 30 seconds; `holdTimeout:` changes that, `null` doesn't hold). Held
  means the server does not send the rest of the configuration (resource pack,
  registries, "finish configuration") until the handler calls `release()`. If
  the time passes first, the client is disconnected.
* `connection.next(channel)` waits for the next payload the client sends on
  `channel`. It returns `null` after its timeout (10 seconds by default), and a
  vanilla client never answers, so always handle `null`. It throws a
  `ConnectionClosedException` if the client left in the meantime.
* Replies are queued from the moment the client connects: one that arrives
  before you call `next` is not lost.
* `connection.brand` is the client brand (`vanilla`, `fabric`, `neoforge`, ...)
  once the server received it. It is usually known after the client's first
  payload, so don't expect it in the first line of the handler.

### Fail closed

A held connection is never left hanging by mistake:

* if the handler **throws**, the error is logged (never crashes the plugin) and
  the client is disconnected with a generic message
  (`failureMessage:`, "Failed to complete the server handshake." by default), so
  internal details don't reach the player;
* if the handler **returns without releasing or disconnecting** a held
  connection, the client is disconnected too (a forgotten `release()` is a bug
  you want to see). Pass `releaseOnReturn: true` to release instead when the
  handler returns normally;
* when the plugin unloads, or the registration is cancelled, clients that are
  still held are disconnected.

### Filtering and per-client timeouts

```dart
context.onConfiguration(
  where: (connection) {
    if (connection.protocolVersion < 769) return false;   // not handled at all
    connection.hold(timeout: const Duration(seconds: 10)); // per client; optional
    return true;
  },
  (connection) async { ... },
);
```

`where` runs synchronously while the server dispatches the start event; it is
the only place `connection.hold` works. If it throws, the error is logged and
the client is not handled (so it is not held).

## API

| | |
| --- | --- |
| `context.onConfiguration(handler, {onPreBrand, preBrandHoldTimeout, holdTimeout, where, onFinish, finishHoldTimeout, onPacket, capturePackets, releaseOnReturn, failureMessage})` | registers the handler, returns a `Subscription` |
| `context.onLogin(handler, {holdTimeout, where, releaseOnReturn, failureMessage})` | the login-phase counterpart |
| `connection.id`, `uuid`, `username`, `protocolVersion`, `brand` | what is known about the client |
| `connection.send(channel, bytes)`, `sendString`, `sendTyped(channel, codec, value)` | send a custom payload |
| `await connection.next(channel, {timeout})`, `nextTyped(channel, codec, {timeout})` | wait for a reply; `null` on timeout |
| `connection.sendPacket(id, bytes)`, `await connection.nextPacket(id, {timeout})` | raw configuration packets |
| `await login.query(channel, bytes, {timeout, queryId})` | login query; `null` = not understood or timeout |
| `connection.release()` | continue the current hold (no-op if it wasn't held); see "Releasing" below |
| `connection.setFlavour(ConnectionFlavour.neoforge)` | marks the connection for the host's play phase (`server.set-connection-flavour`) |
| `connection.stage`, `connection.flavour` | `ConfigurationStage.preBrand`/`start`/`finish`; the flavour set so far |
| `connection.disconnect(reason)` | kick the client; pending `next`s fail |
| `connection.isHeld`, `isReleased`, `isClosed`, `completed`, `await connection.done` | state; `done` completes with whether the client finished |

Channel names are `namespace:path`.

### Packets and codecs

`PacketWriter` and `PacketReader` implement Minecraft's `FriendlyByteBuf`
primitives (usable anywhere, also for play-phase `PluginChannel`s):
VarInt/VarLong, bool, byte/short/int/long (big endian), float/double, UTF-8
strings with a length limit, UUIDs, byte arrays, packed block positions,
optionals and lists. Malformed input throws a `PacketException`; running out of
bytes throws a `PacketUnderflowException` that says how much was missing.

```dart
final handshake = PayloadCodec<(int, String)>.buffer(
  write: (w, v) => w
    ..writeVarInt(v.$1)
    ..writeString(v.$2, maxLength: 64),
  read: (r) => (r.readVarInt(), r.readString(maxLength: 64)),
);
connection.sendTyped(hello, handshake, (1, 'welcome'));
final reply = await connection.nextTyped(ack, handshake);   // (int, String)?
```

`PayloadCodec.buffer` rejects trailing bytes by default. `PayloadCodecs` has
`bytes`, `utf8Text`, `string` and `json`. For the play phase there is
`TypedChannel<T>(name, codec)`, a `PluginChannel` that sends and receives
values.

### Raw events

The wrapper is built on events that stay available:

```dart
context.intercept(Events.configurationPreBrand, (server, e) => e.copyWith(hold: true));   // before the brand
context.intercept(Events.configurationStart, (server, e) => e.copyWith(hold: true));
context.listen(Events.configurationPayload, (server, e) { /* connectionId, channel, data, brand */ });
context.intercept(Events.configurationPacketReceived, (server, e) => e.cancel());
context.intercept(Events.configurationFinish, (server, e) => e.copyWith(hold: true));
context.listen(Events.configurationEnd, (server, e) { /* completed */ });
context.intercept(Events.loginStart, (server, e) => e.copyWith(hold: true));
context.listen(Events.loginQueryAnswer, (server, e) { /* queryId, data (null: not understood) */ });
```

and on the `server` resource: `sendConfigurationPayload`,
`sendConfigurationPacket`, `releaseConfiguration`, `setConnectionFlavour`,
`disconnectConfiguration`,
`sendLoginQuery`, `releaseLogin`, `disconnectLogin`, all keyed by the
`connectionId` (no `Player` exists yet). `hold` has to be set by returning the
changed event from `intercept`, since the server decides what to do when the
start event returns.

## Announcing channels (`minecraft:register`)

Mod loaders only let a client *send* on channels the server announced with a
`minecraft:register` payload (NeoForge throws `UnsupportedOperationException`
otherwise, Fabric's `canSend` is false). A plugin that receives payloads from a
mod therefore announces them first:

```dart
connection.announceChannels(['mymod:ack']);       // configuration phase
player.announceChannels(['mymod:ping']);          // play phase, e.g. on join
```

The client sends its own `minecraft:register` too (listing the channels it
receives), which `connection.next('minecraft:register')` delivers. A vanilla
client sends none, so waiting for it briefly tells modded and vanilla clients
apart without a long timeout. `example/modbridge` does exactly this.

## Raw packets

Custom payloads are only one kind of configuration packet. A loader also sends
and expects its own packets, so the hook exposes the packets themselves: ids
and bodies, without the length prefix or the id.

```dart
context.onConfiguration(
  (connection) async {
    connection.sendPacket(0x0e, body);                       // clientbound, raw
    final reply = await connection.nextPacket(0x02);          // serverbound, raw
    ...
  },
  // Sees every serverbound packet before the server does; true cancels it.
  onPacket: (connection, packetId, payload) => packetId == 0x99,
  // Or only queue them for `nextPacket`:
  // capturePackets: true,
);
```

* `onPacket` runs synchronously in the server's packet loop, so keep it short.
  Cancelling makes the server ignore the packet: use it for packets the server
  would otherwise answer or reject (an answer to a packet only your plugin
  knows about). If it throws, the error is logged and the packet goes on to
  the server.
* Custom payloads are packets too: they arrive in `onPacket` and, separately,
  in `connection.next(channel)`. Cancelling a payload packet in `onPacket`
  does not remove it from the `next` queue.
* Packet ids depend on the protocol version; the plugin has to know them.
* Passing `onPacket` or `capturePackets` makes the server ask the plugin about
  *every* configuration packet; without them it does not.

## Hold points

The server can hold the configuration at three places. Each is released with
`connection.release()`, and they all share **one** `ConfigurationConnection`
(brand, queues and state carry over; `connection.stage` tells where it is):

| stage | handler | hold timeout | when | what `release()` does |
| ----- | ------- | ------------ | ---- | --------------------- |
| `preBrand` | `onPreBrand` | `preBrandHoldTimeout` | right after login was acknowledged, **before** the server's `minecraft:brand` | the server sends the brand, fires the start event and goes on to the **start** hold |
| `start` | the `handler` | `holdTimeout` | after the brand, before the resource pack, registries and tags | the server sends the rest of the configuration (registries, tags, ...) |
| `finish` | `onFinish` | `finishHoldTimeout` | after the registries and tags, right before "finish configuration" | the server sends "finish configuration" |

`onPreBrand` and `onFinish` only exist as hold points if you pass them; the
server only asks the plugin about a stage it has a handler for. Without
`onPreBrand` nothing is held before the brand and the registration behaves
exactly as it did before the stage existed.

### The pre-brand stage

Some mod loaders classify a connection by what the server sends *before* its
brand: NeoForge's client treats the connection as NeoForge from the moment it
receives the `neoforge:register` query, and a brand that arrives first makes it
a non-NeoForge connection for good ([neoforge-protocol.md](neoforge-protocol.md),
"The ordering problem"). `onPreBrand` is the place to talk first:

```dart
context.onConfiguration(
  onPreBrand: (c) async {
    c.send('mymod:probe', const []);
    final answer = await c.next('mymod:probe', timeout: const Duration(seconds: 3));
    if (answer != null) c.setFlavour(ConnectionFlavour.neoforge);   // before releasing
    c.release();            // the server sends its brand, the start hold follows
  },
  (c) async { /* start hold: registries etc., as before */ c.release(); },
);
```

* While held, everything works that works at the start: `send`, `sendPacket`,
  `next`, `nextPacket`, `announceChannels`, and the client's answers arrive.
  Raw packets need `capturePackets: true` (a ping/pong, for example). The
  client's brand is usually known only after its first payload.
* **`setFlavour`** marks the connection with the encoding flavour of its play
  phase (`ConnectionFlavour.vanilla`, the default, or `neoforge`; WIT
  `connection-flavour`). It takes effect at once, is carried over to the player
  when the configuration finishes, and fails (a `ConfigurationException`) once
  the connection is past the configuration or gone. Call it only for a client
  that was really told to be a NeoForge connection: for a client that did not
  get the query the extra bytes of the NeoForge encodings are garbage. Call it
  at the pre-brand or the start stage, never later.
* `where` is asked once per client, at the first stage the registration has:
  the pre-brand event if `onPreBrand` is given (a `hold` requested there is the
  pre-brand hold), the start event otherwise. A client `where` declined is not
  handled at any stage.
* Fail-closed works per stage: a pre-brand handler that throws, or returns
  without releasing or disconnecting, disconnects the client.

### Releasing

`release()` always releases the hold that is active *now*: call it once per
stage, in the handler of that stage.

* A pre-brand release does not finish anything: the server sends the brand,
  the **start event fires**, the `handler` runs with its own hold
  (`holdTimeout`; null means the start is not held) and so on.
* They share one connection but are separate hold points with their own
  timeout (null means no hold at that point).
* Each handler is responsible for the hold that was active when it started.
  If the pre-brand handler is still running when the start hold begins, it
  returning (without releasing) does **not** disconnect the client; likewise
  the start handler is not blamed for the finish hold, and so on.
* A handler that calls `release()` late, while a later hold is already
  active, would release that later hold, so don't release from an earlier
  handler after it started waiting on something that outlives its hold.
* `connection.holdEpoch` counts the holds (1 for the first hold, 2 for the next
  when both hold); `isHeld` tells whether a hold is on.

### The finish hold

```dart
context.onConfiguration(
  (connection) async { /* start: announce, negotiate, release */ },
  onFinish: (connection) async {
    connection.sendPacket(loaderTaskPacket, body);
    if (await connection.nextPacket(taskDonePacket) == null) {
      connection.disconnect('Loader step failed');
      return;
    }
    connection.release();
  },
);
```

It runs after the registries and tags were sent, right before "finish
configuration": mod loaders run their own configuration tasks here (for
example NeoForge's custom configuration tasks).

## Login phase: queries

```dart
context.onLogin((login) async {
  final answer = await login.query(
    'mymod:handshake',
    PacketBuffer.encode((w) => w.writeVarInt(1)),
    timeout: const Duration(seconds: 5),
  );
  if (answer == null) {                       // vanilla, or no answer in time
    login.disconnect('This server needs the My Mod client mod.');
    return;
  }
  login.release();                            // the login finishes
});
```

* The login is **always held** while the handler runs (`holdTimeout`, 30s by
  default); the server then disconnects the client. Queries only work during
  the hold.
* `login.query(channel, data, {timeout})` sends a login query and returns the
  answer: `null` if the client does not understand the query (vanilla clients
  answer "no") or does not answer within `timeout`. It fails with
  `ConnectionClosedException` if the login ended first. Query ids are
  allocated for you from a high range (`0x40000000` and up) to stay clear of
  the small ids proxies (Velocity's modern forwarding) and loaders use; give
  `queryId:` to use a fixed one.
* `release()` ends the login for this connection: the client goes on into the
  configuration phase, where `onConfiguration` takes over. `LoginConnection`
  is closed after `release()` and `disconnect()`, and there is no
  `send`: everything is a query.
* Fail-closed, `where`, `releaseOnReturn`, `failureMessage` and unload
  behavior are identical to `onConfiguration`: a handler that throws or returns
  without releasing or disconnecting disconnects the client with the generic
  message, and held logins are disconnected when the plugin unloads.
* The server reports no end of the login phase, so a client that vanishes
  mid-login is only noticed when the hold timeout (plus 5 seconds) has passed:
  pending queries then fail with a `ConnectionClosedException`.
* Whether `connection.id` is the same in the login and the configuration phase
  is up to the server; match on `uuid`/`username` if you need to link them.

## Sketch: implementing a loader's handshake

This is the shape of a plugin that makes a client with mods feel at home,
using only these primitives. The *content* (packet ids, channel names, byte
layouts) is the loader's protocol, see [loader-notes.md](loader-notes.md) for
what a NeoForge client expects from a server that is not NeoForge.

```dart
context.onConfiguration(
  holdTimeout: const Duration(seconds: 20),
  // 1. Start (held): announce channels, then loader-specific packets.
  (c) async {
    // The server already sent minecraft:brand; a loader classifies the
    // connection when it sees it, so channel announcements come after it
    // (a loader that must come first needs the pre-brand stage, see above).
    // Tell the client which channels we send/accept (minecraft:register is a
    // list of "namespace:path" strings, each ended by a 0 byte):
    c.send('minecraft:register', registerPayload(['mymod:hello_ack']));

    // The client announces what it can receive the same way (this is the
    // cheap "is it modded?" signal, no timeout needed).
    final theirs = await c.next('minecraft:register', timeout: const Duration(seconds: 3));
    final modded = theirs != null && parseRegister(theirs).contains('mymod:hello');

    if (!modded) {
      c.release();                            // let vanilla clients through
      return;
    }

    // Loader-specific packets: raw ids, bodies you build with PacketWriter.
    c.sendPacket(loaderHelloPacketId, PacketBuffer.encode((w) => w.writeVarInt(1)));
    final reply = await c.nextPacket(loaderHelloAckPacketId);
    if (reply == null || !acceptable(reply)) {
      c.disconnect('Incompatible mod versions');
      return;
    }
    c.release();                              // server continues: registries...
  },
  // 2. Finish (held again): the loader's own configuration tasks, which run
  //    after the registries and tags and before the player joins.
  onFinish: (c) async {
    if (c.brand == 'vanilla') { c.release(); return; }
    for (final task in loaderConfigurationTasks) {
      c.sendPacket(task.packetId, task.body);
      if (await c.nextPacket(task.ackPacketId) == null) {
        c.disconnect('Mod configuration failed');
        return;
      }
    }
    c.release();                              // "finish configuration" is sent
  },
  // Loader packets the server would reject as unknown: swallow them.
  onPacket: (c, id, body) => loaderPacketIds.contains(id),
);
```

and for loaders that negotiate in the login phase:

```dart
context.onLogin((login) async {
  final answer = await login.query('loader:handshake', hello);
  if (answer == null) { login.release(); return; }   // not modded: carry on
  ... // possibly more queries
  login.release();
});
```

A loader that must be heard before the brand puts the first part in
`onPreBrand` (see "The pre-brand stage"), `pumpkin_neoforge` does exactly that.

The pieces to watch: a `null` answer or reply is a normal outcome (vanilla
clients) and the plugin decides what it means; every path out of a handler
should `release()` or `disconnect()`; registries cannot be changed from a
plugin, so anything that needs matching registries is out of reach (see
Limitations).

## Lifetimes and timing

* A `ConfigurationConnection` is plain Dart data. Keep it, `await` with it, use
  it from timers: it stays usable until the connection ends. After that
  `send`/`release` throw `ConnectionClosedException` and `next` fails the same
  way (and `disconnect` does nothing).
* The `server` a raw event handler receives is only valid during that callback
  ([lifetimes](lifetimes.md)). The wrapper never keeps it: for each `send`,
  `release` or `disconnect` it asks the plugin's kept `Context`
  (`Plugin.context`) for a fresh server handle and drops it right after. So
  `onConfiguration` has to be called on the context `onLoad` receives (or
  `Plugin.context`), and the calls only work while the plugin is loaded.
* The handler starts one tick (up to 50ms) after the start event, because the
  server only holds once the event has returned. A first `send` therefore
  never races the hold. Timeouts (`next`, hold) have the usual 50ms resolution
  of plugin timers.
* Several `onConfiguration` registrations (or plugins) can coexist. Each
  registration has its own connections and queues, so they don't steal each
  other's replies. How the server combines several holds and releases is up to
  the server.

## Limitations

* **The login phase is only reachable through queries**, held between login
  start and "login finished". Forge's pre-1.20.2 `fml:loginwrapper` style
  handshakes fit that; there is no login end event (see above).
* The pre-brand stage needs a host that fires `configuration-pre-brand-event`
  (Pumpkin does; the stage is only reachable through `onPreBrand`).
* **No registry synchronisation.** A plugin cannot add registry entries, so
  mods that add blocks, items or entities still need the registries to match;
  the plugin can negotiate and refuse, but not make a client compatible.
* **Java Edition only.** Bedrock clients have no custom payloads and never
  appear in these events.
* The `minecraft:brand` channel is handled by the server and not reported as a
  payload; read it from `connection.brand`.
* Nothing is held or reported when no plugin registers a handler.
