// Options and messages of the server side handshake. Binding-free.
import 'protocol.dart' show neoForgeServerConfigFile;

/// How the server opens the negotiation. See docs/neoforge-protocol.md,
/// "The ordering problem".
enum NeoForgeNegotiation {
  /// Announce the server's channels with `minecraft:register` and do the
  /// registry sync over "ad hoc" channels, without the `neoforge:register`
  /// query. The client keeps treating the connection as a non-NeoForge one,
  /// so the play phase uses vanilla encodings: this is what works with a
  /// server whose play phase is vanilla (Pumpkin), and the default.
  adhoc,

  /// The full NeoForge handshake, as a NeoForge server does it: **before the
  /// server's brand** (the pre-brand hold of `Context.onConfiguration`) the
  /// library sends `minecraft:unregister`, `minecraft:register`, the
  /// `neoforge:register` query and a ping, and waits for the client's answer. A
  /// client that answers is a NeoForge client: its channels are negotiated, the
  /// connection is marked as NeoForge in the host
  /// (`ConfigurationConnection.setFlavour`), `neoforge:network` and a second
  /// `minecraft:register` go out, and the brand follows. A client that does not
  /// answer within [NeoForgeServerOptions.announceTimeout] is not NeoForge and
  /// is handled by [NonNeoForgePolicy]. The start hold then does the registry
  /// sync, the finish hold the rest, as in [adhoc].
  ///
  /// The client treats the connection as NeoForge from the query on, so its
  /// play phase differs: the host writes the NeoForge encodings (block
  /// particles carry an extra optional position) for connections the library
  /// marked, and two behaviours need the plugin (elytra, `recipe_content`; see
  /// `NeoForgeServer.installPlay`). Needs a host with the pre-brand hold and
  /// `set-connection-flavour` (Pumpkin's `ConfigurationPreBrandEvent`).
  full,
}

/// What to do with a client that is not a NeoForge client.
enum NonNeoForgePolicy {
  /// Disconnect it with [NeoForgeMessages.notNeoForge] (fail closed).
  reject,

  /// Let it through without any NeoForge exchange (a vanilla client then
  /// does not get the modded entries; its result says so).
  allow,
}

/// Texts shown to the player. `{mods}` is replaced by the mod list, `{detail}`
/// by the reason.
final class NeoForgeMessages {
  final String notNeoForge;
  final String noRegistrySync;
  final String registrySyncTimeout;
  final String negotiationFailed;
  final String taskTimeout;
  final String badReply;
  final String unsupportedCommonVersion;

  const NeoForgeMessages({
    this.notNeoForge =
        'This server requires NeoForge with the mod(s): {mods}. '
        'Install NeoForge and the mod(s) to join.',
    this.noRegistrySync =
        'Your NeoForge cannot synchronise registries ({detail}). '
        'Install the same mod(s) as the server: {mods}.',
    this.registrySyncTimeout =
        'Your game did not accept the server registries in time. '
        'Install the same mod(s) as the server: {mods}.',
    this.negotiationFailed =
        'Incompatible mods: the network channels of your mods do not match '
        'the server. Server mod(s): {mods}.',
    this.taskTimeout = 'The NeoForge handshake step "{detail}" timed out.',
    this.badReply = 'The NeoForge handshake failed: {detail}.',
    this.unsupportedCommonVersion =
        'Unsupported common network version. This installation of NeoForge '
        'only supports: 1',
  });
}

/// Tunables of [NeoForgeHandshake] / `NeoForgeServer`.
final class NeoForgeServerOptions {
  /// How the negotiation starts, see [NeoForgeNegotiation].
  final NeoForgeNegotiation negotiation;

  /// What happens to clients without NeoForge.
  final NonNeoForgePolicy nonNeoForge;

  /// How long to wait for the client's `minecraft:register` (ad hoc) or its
  /// answer to the query (full). A vanilla client sends neither, so this is
  /// also the delay of its join (in full mode a vanilla client is recognised
  /// by its pong sooner, see [preBrandGrace]).
  final Duration announceTimeout;

  /// How long the later steps of the full negotiation wait for the client
  /// (its `minecraft:register`, which comes with its query answer).
  final Duration queryTimeout;

  /// Full mode: how long to wait for the query answer after the client's pong
  /// arrived. A client handles packets in order, so its answer is there
  /// before its pong; a vanilla client answers the ping only, so this is how
  /// quickly one is recognised (instead of after [announceTimeout]).
  final Duration preBrandGrace;

  /// How long the client has to apply the registries and acknowledge them.
  final Duration syncTimeout;

  /// How long each later step (common handshake, data maps, enums, flags)
  /// waits for its reply.
  final Duration taskTimeout;

  /// The hold the server keeps before the brand (full), at the start and at
  /// the finish of the configuration. They must be longer than the steps they
  /// cover; the defaults are.
  final Duration preBrandHoldTimeout;
  final Duration holdTimeout;
  final Duration finishHoldTimeout;

  /// Run the `c:version` / `c:register` exchange (what NeoForge servers do
  /// for every NeoForge client).
  final bool commonHandshake;

  /// Send `neoforge:known_registry_data_maps` even if the spec has no data
  /// maps. By default it is only sent when there are some.
  final bool alwaysNegotiateDataMaps;

  /// Send the extensible enum / feature flag checks even if the spec has
  /// none. By default they are only sent when there is something to check.
  final bool alwaysCheckEnums;
  final bool alwaysCheckFeatureFlags;

  /// Full mode: the file names of NeoForge's own synced server config, sent
  /// empty (so the client uses the defaults) in the finish hold, as a NeoForge
  /// server does and a client classified before the brand expects. The name is
  /// `neoforge-server.toml` at NeoForge 26.3.0; a later commit renamed the config
  /// types (`SERVER` became `SYNCED`: `neoforge-synced.toml`). Which one a
  /// `26.3.0.x` client has is not verified: set this to match your client, or
  /// to an empty list to send none. A file named in
  /// `NeoForgeServerSpec.configFiles` is sent instead of the empty one.
  final List<String> neoForgeConfigFiles;

  final NeoForgeMessages messages;

  const NeoForgeServerOptions({
    this.negotiation = NeoForgeNegotiation.adhoc,
    this.nonNeoForge = NonNeoForgePolicy.reject,
    this.announceTimeout = const Duration(seconds: 3),
    this.queryTimeout = const Duration(seconds: 5),
    this.preBrandGrace = const Duration(seconds: 1),
    this.syncTimeout = const Duration(seconds: 20),
    this.taskTimeout = const Duration(seconds: 10),
    this.preBrandHoldTimeout = const Duration(seconds: 30),
    this.holdTimeout = const Duration(seconds: 45),
    this.finishHoldTimeout = const Duration(seconds: 45),
    this.commonHandshake = true,
    this.alwaysNegotiateDataMaps = false,
    this.alwaysCheckEnums = false,
    this.alwaysCheckFeatureFlags = false,
    this.neoForgeConfigFiles = const [neoForgeServerConfigFile],
    this.messages = const NeoForgeMessages(),
  });
}
