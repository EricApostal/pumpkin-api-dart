# Loader notes: what clients expect from the server

Findings from reading NeoForge's 26.3 source (not from watching a live client,
and NeoForge 26.3 was a beta with `@ApiStatus.Internal` classes, so treat them as
a starting point to verify). They describe what a *plugin* has to do to stand in
for a server that is not running the loader, using the
[configuration hook](configuration.md). `example/modbridge/testclient` has a
`--neoforge-like` mode that enforces the same rules.

In the text below `modbridge:*` are the channels of the example plugin; replace
them with the channels of the mod you target.

## What a NeoForge client expects from a server that is not NeoForge

Source for everything below: NeoForge `26.3.x` branch, files
`network/registration/NetworkRegistry.java`, `client/network/registration/ClientNetworkRegistry.java`,
`network/negotiation/NetworkComponentNegotiator.java`, `network/registration/ChannelAttributes.java`,
`network/payload/{MinecraftRegisterPayload,DinnerboneProtocolUtils}.java` and the patches
`patches/net/minecraft/client/multiplayer/Client{Common,Configuration}PacketListenerImpl.java.patch`
(<https://github.com/neoforged/NeoForge/tree/26.3.x>).

### Not being disconnected

Nothing is required **as long as every payload is registered `optional()`**, which this mod does.

* The NeoForge client detects a non-NeoForge server by itself (`ClientNetworkRegistry.initializeOtherConnection`),
  triggered by the server's `minecraft:brand`, or the `update_enabled_features` packet, or finish-configuration.
  The server does **not** send `neoforge:*` / `c:*` packets (no `neoforge:register` query, no
  `neoforge:network`, no `c:version`/`c:register`, no registry sync).
* In that "other connection" mode NeoForge negotiates against an *empty* server list
  (`NetworkComponentNegotiator.negotiate(server=[], client=registrations)`): optional client payloads are dropped,
  any **non-optional** one aborts the join with *"You are trying to connect to a server that is not running NeoForge,
  but you have mods that require it"*. Hence `optional()` is mandatory for this to work against a plugin.
  Mods that add registry entries, data maps, extensible enums or feature flags are rejected the same way; this mod adds none.
* **Ordering rule:** a modbridge payload that arrives *before* the client has classified the connection hits
  `payloadSetup == null` and the client disconnects with `multiplayer.disconnect.incompatible ... (No Payload Setup)`.
  The classification happens when the client processes the server's `minecraft:brand` payload, so the plugin must not
  send `modbridge:hello` before the brand. The hook as designed (fires after login-ack **and the brand was sent**) satisfies this.

### Custom payloads in both directions

* **Server -> client** (`hello`, `pong`, `toast`): no announcement needed. A clientbound payload whose registration is
  optional is accepted "ad hoc" (`NetworkRegistry.hasAdhocChannel`) and decoded by the registered codec.
* **Client -> server** (`hello_ack`, `ping`): **the client refuses to send a channel the server has not announced.**
  `ClientCommonPacketListenerImpl.send` calls `NetworkRegistry.checkPacket`, which throws
  `UnsupportedOperationException("Payload ... may not be sent to the server!")` unless the id is in the connection's
  negotiated set (empty here), the `c:register` set, or the *ad-hoc* set, which is filled by the server sending a
  `minecraft:register` custom payload. So the plugin must send, **in the configuration phase before `modbridge:hello`**:

  ```text
  S2C custom payload (config)  channel = minecraft:register
                               data    = "modbridge:hello_ack" 0x00        ; null-terminated names, ASCII
                                         6d6f646272696467653a68656c6c6f5f61636b00
  ```

  and, once in play (any time before the player can press K, e.g. on join):

  ```text
  S2C custom payload (play)    channel = minecraft:register
                               data    = "modbridge:ping" 0x00
                                         6d6f646272696467653a70696e6700
  ```

  (`DinnerboneProtocolUtils`: the data is a sequence of `namespace:path` strings, each terminated by a `0x00` byte, no length
  prefix, no varints. Several channels can go in one payload.) NeoForge keeps one ad-hoc set per connection that is not cleared
  at the config->play switch, so announcing both in config would also work for NeoForge, but announcing play channels in play is
  the Fabric-compatible, protocol-correct way: Fabric API also only sends channels the other side registered with
  `minecraft:register` per phase (`AbstractChanneledNetworkAddon.sendableChannels`).
* **Free bonus - detecting the mod without a timeout:** the client announces what it can *receive* with its own
  `minecraft:register` (C2S): in configuration `neoforge:register`, `neoforge:network`, ..., `c:register`, **`modbridge:hello`**
  (the optional configuration channels, `ClientNetworkRegistry.sendInitialListeningChannels`), and again in play
  (`NetworkRegistry.onConfigurationFinished`: `modbridge:pong`, `modbridge:toast`). A vanilla client never sends it. The
  hook's `configuration-payload-event` reports it (only `minecraft:brand` is filtered). A plugin may use it to decide
  "modded client" immediately instead of waiting for the timeout. Same byte format as above.
* The `"1"` version string in `event.registrar("1")` is only compared between two NeoForge peers; a plugin never sees it.

### Can a mod avoid the `minecraft:register` requirement?

Not cleanly. The check lives in the loader's send path, and `minecraft:register` is a single packet that Fabric needs as
well, so the plugin should simply send it (one `send-configuration-payload` call; no host change). Untested alternative:
write the `ServerboundCustomPayloadPacket` straight to the `Connection`, bypassing `ClientCommonPacketListenerImpl.send`;
not recommended.
