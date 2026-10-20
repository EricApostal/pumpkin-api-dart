// The block entity framework. A block entity is a Dart object in plugin memory
// bound to one position; the host holds only its NBT and fires batched tick
// events (plugin-block-entity.wit). See docs/ARCHITECTURE.md, "Block entities".
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'perf.dart';
import 'pos.dart';
import 'worlds.dart';

/// Declares a block entity type: registered with the host, ticked in batches,
/// instantiated by [create].
final class BlockEntityTypeSpec {
  /// `create:<path>`.
  final String key;

  /// Keys of the blocks the type belongs to.
  final List<String> validBlocks;

  /// Creates the (still empty) entity; the store sets [CreateBlockEntity.typeKey]
  /// and reads the saved data afterwards.
  final CreateBlockEntity Function(String worldId, BlockPos pos) create;

  /// Ticks between `tick()` calls: 1 every tick, 0 never ticked.
  final int tickInterval;

  const BlockEntityTypeSpec({
    required this.key,
    required this.validBlocks,
    required this.create,
    this.tickInterval = 1,
  });
}

/// A reusable part of a block entity, like Create's `BlockEntityBehaviour`.
abstract class BlockEntityBehaviour {
  /// Unique among the behaviours of one entity (usually a `static const`).
  String get id;

  late CreateBlockEntity owner;

  void read(NbtCompound tag, {required bool clientPacket}) {}
  void write(NbtCompound tag, {required bool clientPacket}) {}
  void onLoad() {}
  void initialize() {}
  void tick() {}
  void lazyTick() {}
  void onUnload() {}
  void onRemoved() {}
}

/// Base class of every block entity of the mod.
abstract class CreateBlockEntity {
  CreateBlockEntity(this.worldId, this.pos);

  /// `World.getId()` of the world; resolve the world with [world].
  final String worldId;
  final BlockPos pos;

  /// The type key; set by the store before anything else runs.
  late final String typeKey;

  late BlockEntityStore _store;
  final List<BlockEntityBehaviour> _behaviours = [];
  bool _initialized = false;
  bool _removed = false;
  int _lazyCountdown = 0;
  int _tickInterval = 1;
  NbtCompound? _lastClient;

  /// Ticks between `lazyTick()` calls (Create: 10).
  int lazyTickRate = 10;

  /// Whether the entity has client data (the update tag). Set to `false` for
  /// entities the client never reads.
  bool get syncsToClient => true;

  /// The block entity was removed (block broken or replaced).
  bool get removed => _removed;

  /// The kept world, `null` if it is not loaded. Do not dispose it.
  World? get world => _store.worlds.byId(worldId);

  /// The store, for looking up neighbours.
  BlockEntityStore get store => _store;

  // -- Behaviours -------------------------------------------------------------

  T addBehaviour<T extends BlockEntityBehaviour>(T behaviour) {
    behaviour.owner = this;
    _behaviours.add(behaviour);
    return behaviour;
  }

  T? getBehaviour<T extends BlockEntityBehaviour>() {
    for (final b in _behaviours) {
      if (b is T) return b;
    }
    return null;
  }

  // -- Lifecycle hooks (override, call super) ----------------------------------

  /// After the data was read and the entity is in the store.
  void onLoad() {
    for (final b in _behaviours) {
      b.onLoad();
    }
  }

  /// Before the first `tick()`.
  void initialize() {
    for (final b in _behaviours) {
      b.initialize();
    }
  }

  void tick() {
    for (final b in _behaviours) {
      b.tick();
    }
  }

  void lazyTick() {
    for (final b in _behaviours) {
      b.lazyTick();
    }
  }

  /// The chunk unloads; the data stays saved.
  void onUnload() {
    for (final b in _behaviours) {
      b.onUnload();
    }
  }

  /// The block was broken or replaced; the data is gone.
  void onRemoved() {
    for (final b in _behaviours) {
      b.onRemoved();
    }
  }

  // -- NBT ----------------------------------------------------------------------

  /// Loads state from [tag]: the saved data (`clientPacket` false) or the update
  /// tag (true).
  void read(NbtCompound tag, {required bool clientPacket}) {
    for (final b in _behaviours) {
      b.read(tag, clientPacket: clientPacket);
    }
  }

  /// Writes state to [tag]: the saved data (`clientPacket` false) or the client
  /// data (true).
  void write(NbtCompound tag, {required bool clientPacket}) {
    for (final b in _behaviours) {
      b.write(tag, clientPacket: clientPacket);
    }
  }

  // -- Persistence and sync -------------------------------------------------------

  /// The state changed and must be saved (written at the end of the tick, at most
  /// every `save_interval_ticks`).
  void markDirty() {
    if (!_removed) _store._dirty.add(this);
  }

  /// The client must get the new state (written as client data at the end of the
  /// tick). Implies saving.
  void sendData() {
    if (_removed) return;
    _store._dirty.add(this);
    _store._sync.add(this);
  }

  @override
  String toString() => '$typeKey@${pos.x},${pos.y},${pos.z}';
}

/// A block entity whose state is a dart_mappable model [S], stored as one JSON
/// string under `State` (plugin private: the client never reads it). Override
/// [syncsToClient] or `write` for the real client format.
abstract class MappableBlockEntity<S extends Object> extends CreateBlockEntity {
  MappableBlockEntity(super.worldId, super.pos);

  /// The current state.
  late S state;

  /// A new state for an entity without saved data.
  S initialState();

  S stateFromMap(Map<String, dynamic> map);
  Map<String, dynamic> stateToMap(S state);

  @override
  bool get syncsToClient => false;

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final json = tag.getString('State');
    state = json == null ? initialState() : stateFromMap(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (!clientPacket) tag.putString('State', jsonEncode(stateToMap(state)));
  }
}

/// All loaded block entities, keyed by (world, position), kept in step with the
/// host's load, unload and tick events.
final class BlockEntityStore {
  final Worlds worlds;
  final Logger log;

  /// Ticks between writes of dirty entities (not of `sendData`).
  int saveIntervalTicks;

  BlockEntityStore(this.worlds, this.log, {this.saveIntervalTicks = 20});

  final Map<String, BlockEntityTypeSpec> _types = {};
  final Map<String, Map<int, CreateBlockEntity>> _byWorld = {};
  final Set<CreateBlockEntity> _dirty = {};
  final Set<CreateBlockEntity> _sync = {};
  late final TickDispatcher dispatcher = TickDispatcher(this);

  /// Adds the types of the registry (before the first event).
  void registerType(BlockEntityTypeSpec spec) => _types[spec.key] = spec;

  BlockEntityTypeSpec? typeSpec(String key) => _types[key];

  /// The entity at [pos] of world [worldId], or `null`.
  CreateBlockEntity? at(String worldId, BlockPos pos) => _byWorld[worldId]?[packPos(pos.x, pos.y, pos.z)];

  /// Like [at] but only if it is a `T`.
  T? typed<T extends CreateBlockEntity>(String worldId, BlockPos pos) {
    final e = at(worldId, pos);
    return e is T ? e : null;
  }

  /// All loaded entities of a world.
  Iterable<CreateBlockEntity> inWorld(String worldId) => _byWorld[worldId]?.values ?? const [];

  int get count => _byWorld.values.fold(0, (n, m) => n + m.length);

  CreateBlockEntity? _instantiate(String worldId, BlockPos pos, String typeKey) {
    final spec = _types[typeKey];
    if (spec == null) {
      log.warn('No block entity type `$typeKey` is registered (block entity at ${pos.x}, ${pos.y}, ${pos.z}).');
      return null;
    }
    final be = spec.create(worldId, pos);
    be.typeKey = typeKey;
    be._store = this;
    be._tickInterval = spec.tickInterval < 1 ? 1 : spec.tickInterval;
    be._lazyCountdown = be.lazyTickRate;
    return be;
  }

  void _put(CreateBlockEntity be) {
    _byWorld.putIfAbsent(be.worldId, () => {})[packPos(be.pos.x, be.pos.y, be.pos.z)] = be;
  }

  /// Creates the entity of a block that was just placed (idempotent): puts it in
  /// the store, calls `onLoad` and publishes its data so the host has the entity.
  CreateBlockEntity? createAt(World world, BlockPos pos, String typeKey) =>
      Perf.measure('place.createBlockEntity', () => _createAt(world, pos, typeKey));

  CreateBlockEntity? _createAt(World world, BlockPos pos, String typeKey) {
    final worldId = worlds.touch(world);
    final existing = at(worldId, pos);
    if (existing != null && existing.typeKey == typeKey) return existing;
    final be = _instantiate(worldId, pos, typeKey);
    if (be == null) return null;
    _put(be);
    _guard(be, 'onLoad', be.onLoad);
    _publish(be, world);
    return be;
  }

  void _guard(CreateBlockEntity be, String what, void Function() body) {
    try {
      body();
    } catch (e, s) {
      log.error('$what of $be failed', error: e, stackTrace: s);
    }
  }

  /// Writes the entity to the host. A save-only write re-sends the cached
  /// client tag (the host replaces client data on every write).
  void _publish(CreateBlockEntity be, World world, {bool refreshClient = true}) {
    if (!Perf.enabled) return _publishUnmeasured(be, world, refreshClient: refreshClient);
    final watch = Stopwatch()..start();
    try {
      _publishUnmeasured(be, world, refreshClient: refreshClient);
    } finally {
      Perf.record('host.setPluginBlockEntity', watch.elapsedMicroseconds);
    }
  }

  void _publishUnmeasured(
    CreateBlockEntity be,
    World world, {
    required bool refreshClient,
  }) {
    final save = NbtCompound();
    be.write(save, clientPacket: false);
    NbtCompound? client;
    if (be.syncsToClient) {
      client = be._lastClient;
      if (client == null || refreshClient) {
        client = NbtCompound();
        be.write(client, clientPacket: true);
        be._lastClient = client;
      }
    }
    try {
      world.setPluginBlockEntity(be.pos, be.typeKey, save, client: client);
      _unpublished.remove(be);
    } on PluginRegistryException catch (e) {
      // The chunk is not loaded (yet), or the host refused the write. Keep the
      // entity pending: without a host entity it never appears in a block entity
      // tick batch, so nothing would ever tick it and a kinetic block would stay
      // at speed 0 until its network was re-propagated by hand. It is published
      // as soon as the world ticks and the chunk is there.
      _unpublished.add(be);
      log.debug('Deferred writing $be: ${e.message}');
    }
  }

  /// Entities whose first write failed because their chunk was not loaded.
  final Set<CreateBlockEntity> _unpublished = {};

  /// Retries the deferred writes of [world]. Called on every world tick.
  void _publishDeferred(World world) {
    if (_unpublished.isEmpty) return;
    final id = world.getId();
    for (final be in _unpublished.toList()) {
      if (be.worldId != id || be.removed) continue;
      _publish(be, world);
    }
  }

  /// Writes the pending sync and (every [saveIntervalTicks]) dirty entities of
  /// [world].
  void flushWorld(World world, int tick, {bool force = false}) =>
      Perf.measure('tick.flushWorld', () => _flushWorld(world, tick, force: force));

  void _flushWorld(World world, int tick, {bool force = false}) {
    if (_dirty.isEmpty) return;
    final id = world.getId();
    final saveNow = force || tick % saveIntervalTicks == 0;
    // Collect what this world has to write before touching the sets (removing while iterating
    // throws). The old code copied the whole set — every world's entities — on every world tick;
    // this copies only the entities that are actually published now.
    final due = <(CreateBlockEntity, bool)>[];
    for (final be in _dirty) {
      if (be.worldId != id) continue;
      final sync = _sync.contains(be);
      if (!sync && !saveNow) continue;
      due.add((be, sync));
    }
    for (final (be, sync) in due) {
      _dirty.remove(be);
      _sync.remove(be);
      if (!be.removed) _publish(be, world, refreshClient: sync);
    }
  }

  /// Writes everything that is pending (plugin unload).
  void flushAll() {
    for (final be in _dirty.toList()) {
      final world = worlds.byId(be.worldId);
      if (world != null && !be.removed) _publish(be, world, refreshClient: _sync.contains(be));
    }
    _dirty.clear();
    _sync.clear();
  }

  /// Subscribes to the host events. Call once from `Plugin.onLoad`, after the
  /// types were registered.
  void install(Context context) {
    context.listen(Events.blockEntityLoad, (server, e) {
      final worldId = worlds.touch(e.targetWorld);
      final old = at(worldId, e.pos);
      if (old != null) _guard(old, 'onUnload', old.onUnload);
      final be = _instantiate(worldId, e.pos, e.typeKey);
      if (be == null) return;
      _put(be);
      _guard(be, 'read', () => be.read(e.save, clientPacket: false));
      _guard(be, 'onLoad', be.onLoad);
    });
    context.listen(Events.blockEntityUnload, (server, e) {
      final worldId = worlds.touch(e.targetWorld);
      final map = _byWorld[worldId];
      final be = map?.remove(packPos(e.pos.x, e.pos.y, e.pos.z));
      if (be == null) return;
      _dirty.remove(be);
      _sync.remove(be);
      if (e.removed) {
        be._removed = true;
        _guard(be, 'onRemoved', be.onRemoved);
      } else {
        _guard(be, 'onUnload', be.onUnload);
      }
    });
    context.listen(Events.blockEntityTick, (server, e) {
      dispatcher.dispatch(worlds.touch(e.targetWorld), e.positions);
    });
    context.listen(Events.worldTick, (server, e) {
      worlds.touch(e.targetWorld);
      _publishDeferred(e.targetWorld);
      flushWorld(e.targetWorld, e.tick);
    });
  }

  /// Registers the host ticking of every type (after the types are registered
  /// with the host).
  void applyTicking() {
    for (final spec in _types.values) {
      if (spec.tickInterval > 0) BlockEntityRegistries.setTicking(spec.key, spec.tickInterval);
    }
  }
}

/// Calls `tick()` and `lazyTick()` on the entities of a batched tick event.
final class TickDispatcher {
  final BlockEntityStore store;

  TickDispatcher(this.store);

  /// [positions] are the due entities of one type of world [worldId].
  void dispatch(String worldId, List<BlockPos> positions) {
    final map = store._byWorld[worldId];
    if (map == null) return;
    if (Perf.enabled) {
      final watch = Stopwatch()..start();
      try {
        _dispatch(worldId, map, positions);
      } finally {
        Perf.record('tick.blockEntities(${positions.length})', watch.elapsedMicroseconds);
      }
      return;
    }
    _dispatch(worldId, map, positions);
  }

  void _dispatch(
    String worldId,
    Map<int, CreateBlockEntity> map,
    List<BlockPos> positions,
  ) {
    for (final pos in positions) {
      final be = map[packPos(pos.x, pos.y, pos.z)];
      if (be == null || be._removed) continue;
      try {
        if (!be._initialized) {
          be._initialized = true;
          be.initialize();
        }
        be.tick();
        be._lazyCountdown -= be._tickInterval;
        if (be._lazyCountdown <= 0) {
          be._lazyCountdown = be.lazyTickRate;
          be.lazyTick();
        }
      } catch (e, s) {
        store.log.error('Ticking ${be.typeKey} at ${pos.x}, ${pos.y}, ${pos.z} failed', error: e, stackTrace: s);
      }
    }
  }
}
