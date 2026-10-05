# Configuration-phase hook (design)

Mods with their own client side (Fabric, Forge, NeoForge, or any client that
speaks custom payloads) usually negotiate with the server **before the player
joins**, in the *configuration* phase. Until now Pumpkin plugins only saw the
play phase, so a plugin could not take part in such a handshake. This hook adds
it.

```text
login ──► CONFIGURATION ──────────────────────────────► play
          │  configuration-start-event  (plugin may hold)
          │  configuration-payload-event  (client -> plugin)
          │  server.send-configuration-payload (plugin -> client)
          │  server.release-configuration  (continue) / disconnect-configuration
          └─ configuration-end-event
```

## WIT (Pumpkin `pumpkin-plugin-wit/v0.2`)

Events (in `event.wit`): `configuration-start-event`,
`configuration-payload-event`, `configuration-end-event`. Functions on the
`server` resource (in `server.wit`): `send-configuration-payload`,
`release-configuration`, `disconnect-configuration`. A connection is identified
by `connection-id: u64` because no `player` exists yet during configuration.

Semantics:

* `configuration-pre-brand-event` fires right after login is acknowledged,
  **before** the server's brand. A handler sets `hold = true` (and
  `hold-timeout-seconds`, default 30); the server then sends nothing until
  `release-configuration`, which sends the brand and fires the start event. Mod
  loaders that classify the connection by what comes before the brand
  (NeoForge) speak here. `server.set-connection-flavour(connection-id,
  vanilla | neoforge)` marks the connection for the host's play phase (default
  `vanilla`; fails once the configuration ended). Without a handler nothing
  changes. Dart: `Context.onConfiguration(onPreBrand: ...)`, see
  [configuration.md](configuration.md).
* `configuration-start-event` fires after the server brand was sent (right
  after login is acknowledged if nothing held before the brand). A handler sets `hold = true` (and optionally
  `hold-timeout-seconds`, default 30) to pause: the server then does not send
  server links, the resource pack, known packs, registries or "finish
  configuration" until `release-configuration` is called. If the hold times out
  the client is disconnected.
* `configuration-payload-event` fires for every custom payload the client sends
  during configuration, except `minecraft:brand` (the server handles that).
  The `brand` field carries the client brand once known.
* `configuration-end-event` fires when the client finished configuration
  (`completed = true`) or the connection closed earlier.
* Nothing happens (and nothing is held) if no plugin handles the events.

## Not covered

* The login phase (`fml:loginwrapper`-style queries of Forge before 1.20.2).
* Registry synchronisation: a plugin cannot add registry entries; mods that add
  blocks/items/entities still need the registries to match.
* Bedrock.
