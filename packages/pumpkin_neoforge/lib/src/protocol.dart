// Channel ids and enums of NeoForge's network protocol (26.3.x). Binding-free.
// Every value is cited in docs/neoforge-protocol.md.

/// Minecraft's `ConnectionProtocol`, as far as custom payloads use it. The
/// ordinal is what goes on the wire in `neoforge:register` and
/// `neoforge:network`; [id] is the string `c:register` uses.
enum NetworkPhase {
  handshaking(0, 'handshake'),
  play(1, 'play'),
  status(2, 'status'),
  login(3, 'login'),
  configuration(4, 'configuration');

  /// `ConnectionProtocol.ordinal()`.
  final int ordinal;

  /// `ConnectionProtocol.id()`.
  final String id;

  const NetworkPhase(this.ordinal, this.id);

  /// The phase with [ordinal], or null.
  static NetworkPhase? byOrdinal(int ordinal) {
    for (final phase in values) {
      if (phase.ordinal == ordinal) return phase;
    }
    return null;
  }

  /// The phase with the string [id], or null.
  static NetworkPhase? byId(String id) {
    for (final phase in values) {
      if (phase.id == id) return phase;
    }
    return null;
  }
}

/// Minecraft's `PacketFlow`. The ordinal is the wire value.
enum PacketFlow {
  serverbound(0),
  clientbound(1);

  final int ordinal;

  const PacketFlow(this.ordinal);

  static PacketFlow? byOrdinal(int ordinal) {
    for (final flow in values) {
      if (flow.ordinal == ordinal) return flow;
    }
    return null;
  }
}

/// The channel (custom payload) ids of NeoForge's own protocol.
abstract final class NeoForgeChannels {
  // The vanilla "Dinnerbone" registration protocol, which NeoForge uses.
  static const String minecraftRegister = 'minecraft:register';
  static const String minecraftUnregister = 'minecraft:unregister';
  static const String minecraftBrand = 'minecraft:brand';

  // Builtin payloads: usable before any channel negotiation.
  /// Client <-> server: the query (what the client registered) and its reply.
  static const String moddedNetworkQuery = 'neoforge:register';

  /// Server -> client: the negotiated channels.
  static const String moddedNetwork = 'neoforge:network';

  /// Server -> client: negotiation failed (reasons for the mismatch screen).
  static const String moddedNetworkSetupFailed =
      'neoforge:modded_network_setup_failed';
  static const String commonVersion = 'c:version';
  static const String commonRegister = 'c:register';

  /// The channels that may be used before negotiation (`BUILTIN_PAYLOADS`).
  static const List<String> builtin = [
    minecraftRegister,
    minecraftUnregister,
    moddedNetworkQuery,
    moddedNetwork,
    moddedNetworkSetupFailed,
    commonVersion,
    commonRegister,
  ];

  // Registry synchronisation.
  static const String frozenRegistrySyncStart =
      'neoforge:frozen_registry_sync_start';
  static const String frozenRegistry = 'neoforge:frozen_registry';
  static const String frozenRegistrySyncCompleted =
      'neoforge:frozen_registry_sync_completed';

  // Data map negotiation.
  static const String knownRegistryDataMaps =
      'neoforge:known_registry_data_maps';
  static const String knownRegistryDataMapsReply =
      'neoforge:known_registry_data_maps_reply';

  // Extensible enums and feature flags.
  static const String extensibleEnumData = 'neoforge:extensible_enum_data';
  static const String extensibleEnumAck = 'neoforge:extensible_enum_ack';
  static const String featureFlags = 'neoforge:feature_flags';
  static const String featureFlagsAck = 'neoforge:feature_flags_ack';

  /// Server -> client: a synced server config file.
  static const String configFile = 'neoforge:config_file';

  /// Both directions: splits packets that are too large.
  static const String split = 'neoforge:split';

  /// The channels a NeoForge client announces it can *receive* in the
  /// configuration phase (`sendInitialListeningChannels`): the builtin ones
  /// plus every optional configuration payload that flows to the client.
  static const List<String> clientConfigurationListening = [
    ...builtin,
    configFile,
    frozenRegistrySyncStart,
    frozenRegistry,
    frozenRegistrySyncCompleted,
    knownRegistryDataMaps,
    extensibleEnumData,
    featureFlags,
    split,
  ];

  /// The channels a NeoForge server announces it can receive in the
  /// configuration phase (`initializeOtherConnection` on the server): the
  /// builtin ones plus every optional configuration payload that flows to the
  /// server.
  static const List<String> serverConfigurationListening = [
    ...builtin,
    frozenRegistrySyncCompleted,
    knownRegistryDataMapsReply,
    extensibleEnumAck,
    featureFlagsAck,
    split,
  ];

  /// The payloads a client must announce for the registry synchronisation
  /// to work.
  static const List<String> registrySyncRequired = [
    frozenRegistrySyncStart,
    frozenRegistry,
    frozenRegistrySyncCompleted,
  ];
}

/// The `c:` common network version this implementation speaks (the only one
/// that exists).
const int commonNetworkVersion = 1;

/// The vanilla registries a NeoForge server syncs
/// (`NeoForgeRegistriesSetup.VANILLA_SYNC_REGISTRIES`, 29 of them). See
/// docs/neoforge-protocol.md, "Which registries are synced".
const List<String> neoForgeSyncedVanillaRegistries = [
  'minecraft:sound_event',
  'minecraft:mob_effect',
  'minecraft:block',
  'minecraft:entity_type',
  'minecraft:item',
  'minecraft:fluid',
  'minecraft:particle_type',
  'minecraft:block_entity_type',
  'minecraft:menu',
  'minecraft:command_argument_type',
  'minecraft:stat_type',
  'minecraft:villager_type',
  'minecraft:villager_profession',
  'minecraft:data_component_type',
  'minecraft:recipe_serializer',
  'minecraft:attribute',
  'minecraft:potion',
  'minecraft:number_format_type',
  'minecraft:custom_stat',
  'minecraft:position_source_type',
  'minecraft:map_decoration_type',
  'minecraft:consume_effect_type',
  'minecraft:recipe_display',
  'minecraft:slot_display',
  'minecraft:recipe_book_category',
  'minecraft:recipe_type',
  'minecraft:point_of_interest_type',
  'minecraft:game_event',
  'minecraft:debug_subscription',
];

/// The registries NeoForge itself adds with `sync(true)`.
const List<String> neoForgeOwnSyncedRegistries = [
  'neoforge:entity_data_serializers',
  'neoforge:fluid_type',
  'neoforge:holder_set_type',
  'neoforge:ingredient_serializer',
  'neoforge:fluid_ingredient_type',
  'neoforge:synced_attachment_types',
];

/// The configuration-phase ping and pong: packet id 5 in both directions in
/// the 26.3 protocol (neoforge-protocol.md, "Configuration packets"); the body
/// is one big endian `int`. A NeoForge server pings right after its query, and
/// every client, vanilla too, answers with the same `int`.
const int configurationPingPacketId = 5;
const int configurationPongPacketId = 5;
const List<int> configurationPingBody = [0, 0, 0, 0];

/// The name of the server config file a NeoForge server syncs
/// (`neoforge:config_file`).
const String neoForgeServerConfigFile = 'neoforge-server.toml';

/// The attributes NeoForge adds to `minecraft:attribute`, in registration order
/// (`NeoForgeMod` at `6dc5dfc`, lines 202, 213, 221: `ATTRIBUTES.register`).
/// A client's ids for them follow the vanilla attributes (vanilla count, then
/// these in this order), unless the server syncs the registry and numbers them
/// itself. `neoforge:gliding_flight` is the one that lets a NeoForge client
/// start an elytra glide.
const List<String> neoForgeOwnAttributes = [
  'neoforge:swim_speed',
  'neoforge:creative_flight',
  'neoforge:gliding_flight',
];
