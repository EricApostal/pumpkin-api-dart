// Describes the NeoForge server a plugin pretends to be: its mods, registries
// and payload channels, and how the handshake behaves. Binding-free.
import 'dart:typed_data';

import 'identifier.dart';
import 'payloads.dart';
import 'protocol.dart';
import 'registrations.dart';
import 'vanilla.dart';

/// A mod the server "has". NeoForge 26.3 has no mod list handshake, so this is
/// only used for messages and to name the mod behind a payload channel on
/// the client's mismatch screen.
final class NeoForgeModInfo {
  /// The mod id, which is the namespace of its registry entries and channels.
  final String id;
  final String version;

  /// Shown to the player.
  final String displayName;

  const NeoForgeModInfo({
    required this.id,
    required this.version,
    String? displayName,
  }) : displayName = displayName ?? id;

  @override
  String toString() => '$displayName ($id $version)';
}

/// One registry the server synchronises: its complete, ordered entry list
/// (the index is the numeric id the client will use).
///
/// The list must be *complete*: the client rebuilds its id table from it, so
/// an entry the client has but the list lacks loses its id, and a gap in the
/// ids breaks iteration. For a vanilla registry use [RegistrySpec.vanillaPlus].
final class RegistrySpec {
  /// The registry key, e.g. `minecraft:item`.
  final String key;

  /// All entries in id order.
  final List<String> entries;

  /// Old name -> current name (rarely needed).
  final Map<String, String> aliases;

  /// A registry with exactly [entries].
  factory RegistrySpec(
    String key,
    Iterable<String> entries, {
    Map<String, String> aliases = const {},
  }) {
    final list = List<String>.unmodifiable([
      for (final e in entries) normalizeIdentifier(e),
    ]);
    final seen = <String>{};
    for (final entry in list) {
      if (!seen.add(entry)) {
        throw ArgumentError.value(entry, 'entries', 'is listed twice in $key');
      }
    }
    return RegistrySpec._(normalizeIdentifier(key), list, aliases);
  }

  RegistrySpec._(this.key, this.entries, this.aliases);

  /// The vanilla entries of [key] (generated from Pumpkin's assets, so they
  /// carry the ids Pumpkin uses) followed by the mod's [additions], in the
  /// order the mod registers them. That is also how a real NeoForge server
  /// numbers them: vanilla first, modded entries appended.
  factory RegistrySpec.vanillaPlus(String key, Iterable<String> additions) {
    final id = normalizeIdentifier(key);
    final vanilla = VanillaRegistries.require(id);
    return RegistrySpec(id, [...vanilla, ...additions]);
  }

  /// The number of entries.
  int get length => entries.length;

  @override
  String toString() => 'RegistrySpec($key, $length entries)';
}

/// A custom payload channel of the mod (what the mod registered with
/// `RegisterPayloadHandlersEvent`). Only needed for mods that have their own
/// networking; Lonsdaleite has none.
final class PayloadChannelSpec {
  final String id;
  final String version;

  /// The protocols the payload may be sent in.
  final Set<NetworkPhase> phases;

  /// The direction, or null for both.
  final PacketFlow? flow;

  /// Whether a peer without the channel may still connect.
  final bool optional;

  PayloadChannelSpec({
    required String id,
    required this.version,
    this.phases = const {NetworkPhase.play},
    this.flow,
    this.optional = false,
  }) : id = normalizeIdentifier(id) {
    for (final phase in phases) {
      if (phase != NetworkPhase.play && phase != NetworkPhase.configuration) {
        throw ArgumentError.value(
          phase,
          'phases',
          'payloads exist in the configuration and play phases only',
        );
      }
    }
  }

  QueryComponent toComponent() =>
      QueryComponent(id: id, version: version, flow: flow, optional: optional);
}

/// A registry data map of the server (`neoforge:known_registry_data_maps`).
final class DataMapSpec {
  final String registry;
  final String id;

  /// Whether a client without it must be refused.
  final bool mandatory;

  DataMapSpec({
    required String registry,
    required String id,
    this.mandatory = false,
  }) : registry = normalizeIdentifier(registry),
       id = normalizeIdentifier(id);
}

/// What a plugin tells the library about the server it pretends to be.
final class NeoForgeServerSpec {
  final List<NeoForgeModInfo> mods;

  /// The registries to synchronise. Only registries that contain modded
  /// entries need to be here; the client keeps its own (vanilla-compatible)
  /// ids for the others.
  final List<RegistrySpec> registries;

  /// The payload channels the mods registered.
  final List<PayloadChannelSpec> channels;

  /// The data maps the server has.
  final List<DataMapSpec> dataMaps;

  /// The networked extensible enums and their additions (usually none).
  final List<EnumEntry> extensibleEnums;

  /// Modded feature flags (usually none).
  final List<String> featureFlags;

  /// Server config files to sync, by file name (`neoforge-server.toml`).
  final Map<String, Uint8List> configFiles;

  NeoForgeServerSpec({
    this.mods = const [],
    Iterable<RegistrySpec> registries = const [],
    this.channels = const [],
    this.dataMaps = const [],
    this.extensibleEnums = const [],
    Iterable<String> featureFlags = const [],
    this.configFiles = const {},
  }) : registries = List.unmodifiable(registries),
       featureFlags = [for (final f in featureFlags) normalizeIdentifier(f)] {
    final keys = <String>{};
    for (final registry in this.registries) {
      if (!keys.add(registry.key)) {
        throw ArgumentError.value(
          registry.key,
          'registries',
          'is listed twice',
        );
      }
    }
    final ids = <String>{};
    for (final channel in channels) {
      if (!ids.add(channel.id)) {
        throw ArgumentError.value(channel.id, 'channels', 'is listed twice');
      }
    }
  }

  /// A spec whose registries are the vanilla registries plus [additions]
  /// (registry key -> the mod's entries in registration order). The common
  /// case: a mod that adds items and blocks.
  ///
  /// ```dart
  /// final spec = NeoForgeServerSpec.vanillaPlus(
  ///   mods: [NeoForgeModInfo(id: 'lonsdaleite', version: '2.3.0')],
  ///   additions: {
  ///     'minecraft:block': ['lonsdaleite:lonsdaleite_wardframe'],
  ///     'minecraft:item': ['lonsdaleite:lonsdaleite_wardframe', ...],
  ///   },
  /// );
  /// ```
  factory NeoForgeServerSpec.vanillaPlus({
    List<NeoForgeModInfo> mods = const [],
    required Map<String, Iterable<String>> additions,
    List<PayloadChannelSpec> channels = const [],
    List<DataMapSpec> dataMaps = const [],
    List<EnumEntry> extensibleEnums = const [],
    Iterable<String> featureFlags = const [],
    Map<String, Uint8List> configFiles = const {},
  }) => NeoForgeServerSpec(
    mods: mods,
    registries: [
      for (final entry in additions.entries)
        RegistrySpec.vanillaPlus(entry.key, entry.value),
    ],
    channels: channels,
    dataMaps: dataMaps,
    extensibleEnums: extensibleEnums,
    featureFlags: featureFlags,
    configFiles: configFiles,
  );

  /// The display name of the mod that owns channels in [namespace], or null.
  String? modName(String namespace) {
    for (final mod in mods) {
      if (mod.id == namespace) return mod.displayName;
    }
    return null;
  }

  /// The channels per protocol as the server registers them: NeoForge's own
  /// plus the mod's.
  Map<NetworkPhase, List<QueryComponent>> get allChannels => {
    for (final phase in [NetworkPhase.configuration, NetworkPhase.play])
      phase: [
        ...?neoForgeOwnRegistrations[phase],
        for (final c in channels)
          if (c.phases.contains(phase)) c.toComponent(),
      ],
  };

  /// The mod's configuration channels the server can receive
  /// (serverbound or both directions); they are announced with
  /// `minecraft:register` so the client may send on them.
  List<String> get configurationChannelsToServer => [
    for (final c in channels)
      if (c.phases.contains(NetworkPhase.configuration) &&
          c.flow != PacketFlow.clientbound)
        c.id,
  ];

  /// The names of the registries that are synchronised.
  List<String> get registryKeys => [for (final r in registries) r.key];
}
