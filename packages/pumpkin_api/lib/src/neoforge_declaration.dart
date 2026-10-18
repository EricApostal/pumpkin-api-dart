import 'bindings.g.dart' as generated;
import 'bindings.g.dart' show ChannelFlow, ChannelPhase, Context, Player;
import 'host_result.dart';
import 'uuid_ext.dart';

/// What to do with a client that does not speak NeoForge (vanilla, Fabric).
enum NonNeoForgeClientPolicy {
  /// Disconnect it. If any plugin declares this, such clients are refused.
  reject,

  /// Let it join without the NeoForge exchange.
  allow;

  generated.NonNeoforgePolicy get _wire => switch (this) {
    reject => generated.NonNeoforgePolicy.reject,
    allow => generated.NonNeoforgePolicy.allow,
  };
}

/// The mod a declaration is for. NeoForge has no mod list handshake: the name
/// only shows in messages and on the client's mismatch screen for the channels
/// in the mod's namespace.
final class NeoForgeMod {
  /// The mod id, the namespace of its channels and registry entries.
  final String id;
  final String version;

  /// Shown to players, defaults to the id.
  final String? displayName;

  const NeoForgeMod({required this.id, required this.version, this.displayName});
}

/// A custom payload channel of the mod (`RegisterPayloadHandlersEvent`).
final class NeoForgeChannel {
  /// Full resource location, `namespace:path`.
  final String id;
  final String version;

  /// The phases the channel exists in, at least one.
  final List<ChannelPhase> phases;
  final ChannelFlow flow;

  /// Whether a peer without the channel may still connect.
  final bool optional;

  const NeoForgeChannel({
    required this.id,
    required this.version,
    this.phases = const [ChannelPhase.play],
    this.flow = ChannelFlow.both,
    this.optional = false,
  });

  /// A play-phase channel flowing from the client to the server.
  const NeoForgeChannel.serverbound(this.id, this.version, {this.optional = false})
    : phases = const [ChannelPhase.play],
      flow = ChannelFlow.serverbound;

  /// A play-phase channel flowing from the server to the client.
  const NeoForgeChannel.clientbound(this.id, this.version, {this.optional = false})
    : phases = const [ChannelPhase.play],
      flow = ChannelFlow.clientbound;
}

/// Entries the plugin adds to a synced registry, after the entries the host
/// knows (vanilla and the ones registered through the registry interfaces). For
/// a registry the host does not know, the entries are the whole registry.
final class NeoForgeRegistryAddition {
  /// Registry key, `minecraft:block` or `mymod:thing`.
  final String key;

  /// Entry keys in registration order.
  final List<String> entries;

  const NeoForgeRegistryAddition(this.key, this.entries);
}

/// A server config file sent to clients (`neoforge:config_file`).
final class NeoForgeConfigFile {
  /// File name, for example `mymod-server.toml`.
  final String name;
  final List<int> content;

  const NeoForgeConfigFile(this.name, [this.content = const []]);
}

/// An entry of a datapack registry added to the registry data NeoForge clients
/// get.
final class NeoForgeDatapackEntry {
  /// Registry, for example `minecraft:damage_type` or `mymod:thing`.
  final String registry;

  /// Entry key, `namespace:path`.
  final String id;

  /// The entry as network NBT (a nameless compound), `null` for an entry whose
  /// data the client has.
  final List<int>? data;

  const NeoForgeDatapackEntry(this.registry, this.id, [this.data]);
}

/// A registry data map (`neoforge:known_registry_data_maps`).
final class NeoForgeDataMap {
  final String registry;
  final String id;

  /// Whether a client without it is refused.
  final bool mandatory;

  const NeoForgeDataMap(this.registry, this.id, {this.mandatory = false});
}

/// Everything a plugin tells the NeoForge handshake. The host runs the
/// handshake; see `docs/neoforge-host.md`.
///
/// ```dart
/// context.declareNeoForge(
///   NeoForgeDeclaration(
///     mod: NeoForgeMod(id: 'mymod', version: '1.0.0'),
///     channels: [NeoForgeChannel.clientbound('mymod:sync', '1')],
///     registries: [NeoForgeRegistryAddition('minecraft:item', ['mymod:gem'])],
///     policy: NonNeoForgeClientPolicy.allow,
///   ),
/// );
/// ```
final class NeoForgeDeclaration {
  final NeoForgeMod mod;
  final List<NeoForgeChannel> channels;
  final List<NeoForgeRegistryAddition> registries;
  final List<NeoForgeConfigFile> configFiles;
  final List<NeoForgeDatapackEntry> datapackEntries;
  final List<NeoForgeDataMap> dataMaps;

  /// Modded feature flags, `namespace:path`.
  final List<String> featureFlags;
  final NonNeoForgeClientPolicy policy;

  /// Shown to rejected clients, `{mods}` is replaced by the mod list.
  final String? rejectMessage;

  const NeoForgeDeclaration({
    required this.mod,
    this.channels = const [],
    this.registries = const [],
    this.configFiles = const [],
    this.datapackEntries = const [],
    this.dataMaps = const [],
    this.featureFlags = const [],
    this.policy = NonNeoForgeClientPolicy.allow,
    this.rejectMessage,
  });

  generated.Declaration toWire() => generated.Declaration(
    modInfo: generated.ModInfo(id: mod.id, version: mod.version, displayName: mod.displayName),
    channels: [
      for (final c in channels)
        generated.NetworkChannel(
          id: c.id,
          version: c.version,
          phases: c.phases,
          flow: c.flow,
          optional: c.optional,
        ),
    ],
    registries: [for (final r in registries) generated.SyncedRegistry(key: r.key, entries: r.entries)],
    configFiles: [for (final f in configFiles) generated.ConfigFile(name: f.name, content: f.content)],
    datapackEntries: [
      for (final e in datapackEntries) generated.DatapackEntry(registry: e.registry, id: e.id, data: e.data),
    ],
    dataMaps: [
      for (final d in dataMaps) generated.DataMap(registry: d.registry, id: d.id, mandatory: d.mandatory),
    ],
    featureFlags: featureFlags,
    nonNeoforge: policy._wire,
    rejectMessage: rejectMessage,
  );
}

/// The NeoForge client handshake (`neoforge.wit`). Needs
/// `Permissions.neoforge` and runs while the server loads.
extension NeoForgeHandshakeApi on Context {
  /// Sets the declaration of this plugin (a later call replaces it). Throws a
  /// [HostException] for an invalid identifier or channel, duplicate entries, a
  /// missing permission or when players can connect already.
  void declareNeoForge(NeoForgeDeclaration declaration) =>
      unwrapHost(generated.neoforge.declare(declaration: declaration.toWire()), 'Declaring ${declaration.mod.id} to NeoForge');

  /// Declares the recipe types the plugin's client mod syncs
  /// (`neoforge:recipe_content`), for example `minecraft:crafting` or
  /// `create:pressing`. Vanilla types are sent from the server's recipes,
  /// recipes of other types only with the network data given to
  /// `CustomRecipeBuilder.networkData`. Replaces the previous list; only possible
  /// before players can connect. Throws a [HostException] on failure.
  void declareSyncedRecipeTypes(List<String> types) => unwrapHost(
    generated.neoforge.declareSyncedRecipeTypes(types: types),
    'Declaring the synced recipe types',
  );

  /// Replaces a synced config file of the declared mod [modId] and sends it to
  /// the connected NeoForge players (`neoforge:config_file`). Players that join
  /// later get it with the handshake. Throws a [HostException] on failure.
  void updateNeoForgeConfigFile(String modId, String fileName, List<int> content) => unwrapHost(
    generated.neoforge.updateConfigFile(modId: modId, fileName: fileName, content: content),
    'Updating the config file $fileName',
  );

  /// Removes the declaration of this plugin.
  void withdrawNeoForge() => generated.neoforge.withdraw();

  /// Whether the connection of the player [playerUuid] completed the NeoForge
  /// handshake.
  bool isNeoForgePlayer(String playerUuid) => generated.neoforge.isNeoforgePlayer(playerUuid: playerUuid);
}

/// Whether a player is a NeoForge client.
extension NeoForgePlayerApi on Player {
  /// Whether this player's connection completed the NeoForge handshake.
  bool get isNeoForge => generated.neoforge.isNeoforgePlayer(playerUuid: getId().asString);
}
