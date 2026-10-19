import 'dart:typed_data';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'geometry.dart' show Cuboid;
import 'host_result.dart';

/// An entity type to register (`entity-registry.wit`).
///
/// ```dart
/// final id = EntityRegistries.register(
///   const EntityTypeSpec(key: 'my_plugin:seat', width: 0.1, height: 0.1,
///       trackingRange: 8, summonable: false),
/// );
/// final seat = await world.spawnPluginEntity('my_plugin:seat', (x, y, z));
/// ```
final class EntityTypeSpec {
  /// `namespace:path`; the `minecraft` namespace is reserved.
  final String key;

  final EntityCategory category;

  /// Hitbox size in blocks (0 to 64).
  final double width;
  final double height;

  /// Height of the eyes; 85% of [height] if `null`.
  final double? eyeHeight;

  final bool fireImmune;

  /// How far clients see it, in chunks (at most 256). 0: never sent.
  final int trackingRange;

  /// Ticks between position updates, at least 1.
  final int updateInterval;

  final bool trackDeltas;
  final bool summonable;
  final bool saveable;
  final bool pickable;
  final bool collidable;

  /// Whether other entities push it away when they overlap.
  final bool pushable;

  /// Whether projectiles pass through the riders of the entity. Opposite of
  /// vanilla and kept for compatibility: prefer the `projectilesHitRiders`
  /// entity flag (`EntityFlag`).
  final bool ignoreRidersHit;

  /// Encoded entity metadata a new entity starts with (at most 8192 bytes).
  final List<int> defaultSyncedData;

  /// Custom payload channel sent after the add-entity packet to every client
  /// that starts tracking an entity of the type.
  final String? spawnDataChannel;

  const EntityTypeSpec({
    required this.key,
    required this.width,
    required this.height,
    this.category = EntityCategory.misc,
    this.eyeHeight,
    this.fireImmune = false,
    this.trackingRange = 8,
    this.updateInterval = 3,
    this.trackDeltas = true,
    this.summonable = true,
    this.saveable = true,
    this.pickable = true,
    this.collidable = false,
    this.pushable = true,
    this.ignoreRidersHit = false,
    this.defaultSyncedData = const [],
    this.spawnDataChannel,
  });

  generated.EntityTypeDefinition toWire() => generated.EntityTypeDefinition(
    key: key,
    category: category,
    width: width,
    height: height,
    eyeHeight: eyeHeight,
    fireImmune: fireImmune,
    trackingRange: trackingRange,
    updateInterval: updateInterval,
    trackDeltas: trackDeltas,
    summonable: summonable,
    saveable: saveable,
    pickable: pickable,
    collidable: collidable,
    pushable: pushable,
    ignoreRidersHit: ignoreRidersHit,
    defaultSyncedData: defaultSyncedData,
    spawnDataChannel: spawnDataChannel,
  );
}

/// The host's entity type registry. Registration needs
/// [Permissions.registryEntities] and only works while the server loads.
/// Vanilla types have the ids `0..vanillaCount`, custom ones follow.
abstract final class EntityRegistries {
  /// Registers [type] and returns its network id (the same definition again
  /// returns the existing id). Throws a [HostException] on failure.
  static int register(EntityTypeSpec type) => unwrapHost(
    generated.entityRegistry.registerEntityType(definition: type.toWire()),
    'Registering the entity type ${type.key}',
  );

  /// Registers an entity data serializer for entries of the synced data
  /// (`neoforge:entity_data_serializers`) and returns its id: 256 (NeoForge's
  /// `VANILLA_SERIALIZER_LIMIT`) plus the registration order. A modded client
  /// must register a serializer of the same key. Registering a key again returns
  /// its id. Needs [Permissions.registryEntities]; registration closes with the
  /// others.
  static int registerDataSerializer(String key) => unwrapHost(
    generated.entityRegistry.registerEntityDataSerializer(key: key),
    'Registering the entity data serializer $key',
  );

  /// Registers the entity type tag [tag] (`mymod:flyers`) with [entries], entity type keys.
  /// Throws a [HostException] on failure.
  static void registerTag(String tag, List<String> entries) => unwrapHost(
    generated.entityRegistry.registerEntityTypeTag(tag: tag, entries: entries),
    'Registering the entity type tag $tag',
  );

  /// The id of the entity type [key], vanilla or custom.
  static int? idOf(String key) => generated.entityRegistry.getEntityTypeId(key: key);

  /// The number of vanilla entity types (the id of the first custom one).
  static int get vanillaCount => generated.entityRegistry.getVanillaEntityTypeCount();
}

/// Ticking entities for plugins (`entity-ticking.wit`).
extension EntityTickingApi on Context {
  /// Makes the server fire `Events.entityTick` for each entity of [type]
  /// every [interval] ticks (spread over the interval by entity id). 0 stops
  /// it. Applies to every plugin that listens. Players use
  /// `Events.playerTick`.
  void tickEntities(EntityType type, {required int interval}) =>
      generated.entityTicking.setEntityTicking(entityType: type, interval: interval);

  /// Like [tickEntities] for an entity type registered by a plugin, by its
  /// [key]. Returns false when no type has the key.
  bool tickPluginEntities(String key, {required int interval}) =>
      generated.entityTicking.setPluginEntityTicking(key: key, interval: interval);
}

/// Plugin entities and item entities of a [World].
extension WorldEntities on World {
  /// Spawns an entity of a registered plugin type at [pos]. [syncedData] and
  /// [spawnData] are the encoded metadata and the spawn payload.
  Future<Entity> spawnPlugin(
    String typeKey,
    (double, double, double) pos, {
    List<int>? syncedData,
    List<int>? spawnData,
  }) => unwrapHostAsync(
    spawnPluginEntity(typeKey: typeKey, pos: pos, syncedData: syncedData, spawnData: spawnData),
    'Spawning $typeKey',
  );

  /// Drops [stack] as an item entity at [pos]. The stack is borrowed: it keeps
  /// its count. Returns `null` if nothing could be spawned.
  Future<ItemEntity?> dropItem(
    (double, double, double) pos,
    ItemStack stack, {
    (double, double, double)? velocity,
    int? pickupDelay,
  }) => spawnItem(pos: pos, stack: stack, velocity: velocity, pickupDelay: pickupDelay);

  /// The entities within [box] that match [filter] as cheap snapshots (no
  /// resources to release).
  List<EntitySnapshot> entitiesIn(
    Cuboid box, {
    EntityFilter filter = const EntityFilterAll(),
  }) => getEntitiesInBox(
    min: (box.min.$1.toDouble(), box.min.$2.toDouble(), box.min.$3.toDouble()),
    max: (box.max.$1 + 1.0, box.max.$2 + 1.0, box.max.$3 + 1.0),
    filter: filter,
  );

  /// The dropped items within [box].
  List<ItemEntity> itemsIn(Cuboid box) => getItemEntitiesInBox(
    min: (box.min.$1.toDouble(), box.min.$2.toDouble(), box.min.$3.toDouble()),
    max: (box.max.$1 + 1.0, box.max.$2 + 1.0, box.max.$3 + 1.0),
  );
}

/// The data of an entity of a plugin type.
extension PluginEntityData on Entity {
  /// The registered key of the type, `null` for vanilla entities.
  String? get pluginTypeKey => getPluginTypeKey();

  /// The encoded synced data (entity metadata), `null` for vanilla entities.
  Uint8List? get pluginSyncedData {
    final data = getPluginSyncedData();
    return data == null ? null : Uint8List.fromList(data);
  }

  /// Sets one entry of the synced data: [data] is the serializer id (a var int)
  /// followed by the encoded value, [index] the entry's index (0 to 254). It is
  /// sent to the clients tracking the entity and, after the blob of
  /// [setSyncedData], to the ones that start to. Empty data forgets the entry on
  /// the server (clients keep what they got). Entries are saved with the entity.
  void setSyncedEntry(int index, List<int> data) => unwrapHost(
    setPluginSyncedEntry(index: index, data: data),
    'Setting synced entry $index',
  );

  /// Sets where [passenger] sits relative to this entity. The server places it
  /// there every tick of the entity (plugin entities only); clients take the
  /// offset from the plugin's synced data. Not saved.
  void setPassengerSeat(Entity passenger, double x, double y, double z) => unwrapHost(
    setPassengerOffset(passenger: passenger, x: x, y: y, z: z),
    'Setting the passenger offset',
  );

  /// Overrides how often the position is sent ([updateInterval] ticks, at least
  /// 1, 0 keeps the type's) and whether movement is sent as deltas (`null`
  /// keeps the type's). A shorter interval means smaller steps on the client.
  void setTracking({int updateInterval = 0, bool? trackDeltas}) => unwrapHost(
    setPluginTracking(updateInterval: updateInterval, trackDeltas: trackDeltas),
    'Setting the tracking',
  );

  /// Whether the movement packets of the client that drives this plugin vehicle
  /// are applied (within 16 blocks of the server position). Off by default: the
  /// plugin moves its vehicles and gets `Events.pluginVehicleInput` for the
  /// input of the riders.
  void acceptClientMovement(bool accept) => unwrapHost(
    setPluginAcceptClientMovement(accept: accept),
    'Setting the client movement',
  );

  /// Moves the entity by [delta]. With [collide] blocks stop it like they stop
  /// a mob (set the velocity and call this every tick, gravity is yours).
  /// Returns the distance moved. Not for players.
  (double, double, double) moveBy((double, double, double) delta, {bool collide = true}) =>
      moveEntity(delta: delta, collide: collide);

  /// Replaces the synced data and sends it to the clients tracking the entity.
  void setSyncedData(List<int> data) =>
      unwrapHost(setPluginSyncedData(data: data), 'Setting the synced data');

  /// The spawn payload sent to clients that start tracking the entity.
  Uint8List? get pluginSpawnData {
    final data = getPluginSpawnData();
    return data == null ? null : Uint8List.fromList(data);
  }

  /// Replaces the spawn payload.
  void setSpawnData(List<int> data) =>
      unwrapHost(setPluginSpawnData(data: data), 'Setting the spawn data');

  /// Resizes the hitbox of the entity.
  void resize(double width, double height) =>
      unwrapHost(setPluginSize(width: width, height: height), 'Resizing the entity');
}
