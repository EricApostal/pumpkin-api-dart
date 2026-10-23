// The host implementation of Simulated over Pumpkin.
//
// It adapts a `pumpkin_api` world to the three interfaces the content asks for:
// sable's `SableLevel`, the assembly's `SimAssemblyWorld` and the disassembly's
// `SimAssemblyEntities`. The block movement rules are Create's own
// `BlockMovementChecks`, so an assembler captures exactly what a contraption
// would.
//
// Host: this file uses `pumpkin_api`.
//
// Java: the NeoForge/Fabric platform classes, collapsed into one class.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/core/level.dart' show PushReaction;
import 'package:create/src/contraptions/core/movement_checks.dart' show BlockMovementChecks;
import 'package:create/src/contraptions/core/structure_info.dart' show DefaultContraptionSettings;
import 'package:create/src/contraptions/entity/host_contraption_entities.dart' show HostContraptionLevel;
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/worlds.dart';
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show SableLevel, SubLevel, SubLevelContainer;

import '../config/sim_config_service.dart';
import '../service/sim_services.dart';
import '../content/entities/honey_glue/honey_glue_entity.dart';
import '../content/entities/honey_glue/honey_glue_logic.dart';
import '../util/assembly/sim_assembly_contraption.dart';
import '../util/host_calls.dart';
import '../util/sim_assembly_helper.dart';
import 'simulated_host.dart';

/// A world as sable's sub-level model sees it.
final class PumpkinSableLevel implements SableLevel {
  PumpkinSableLevel(this._world);

  /// The world id and a handle that survives its callback (see `WorldRef`).
  final WorldRef _world;

  /// A handle that is valid right now.
  World get world => _world.world;

  @override
  String get dimensionId => world.dimension;

  @override
  bool get isClientSide => false;

  @override
  int get minY => world.minY;

  /// HOST GAP: the plugin API does not expose `Level.getMaxY`; 26.x worlds are
  /// 384 blocks tall, which is what the assembler's bounds checks use.
  @override
  int get maxY => world.minY + 384;

  @override
  int get gameTime => world.worldAge;

  /// HOST GAP: the plugin API has no biome lookup by position.
  @override
  String? biomeAt(int x, int y, int z) => null;

  @override
  int get sectionsCount => (maxY - minY) >> 4;
}

/// The world as the assembly sees it.
final class PumpkinSimAssemblyWorld implements SimAssemblyWorld {
  PumpkinSimAssemblyWorld(this._world, this.blockEntities);

  /// The world id and a handle that survives its callback (see `WorldRef`).
  final WorldRef _world;
  final BlockEntityStore blockEntities;

  /// The level of the world the ref resolves, rebuilt when that handle changed
  /// (a world that unloaded and loaded again hands out a new one).
  HostContraptionLevel? _level;
  World? _levelWorld;

  /// A handle that is valid right now.
  World get world => _world.world;

  HostContraptionLevel get _hostLevel {
    final world = _world.world;
    final cached = _level;
    if (cached != null && identical(_levelWorld, world)) return cached;
    _levelWorld = world;
    return _level = HostContraptionLevel(world, blockEntities, DefaultContraptionSettings());
  }

  @override
  BState stateAt(Pos pos) => _hostLevel.stateAt(pos);

  @override
  bool isLoaded(Pos pos) => _hostLevel.isLoaded(pos);

  @override
  bool isOutsideBuildHeight(Pos pos) => _hostLevel.isOutsideBuildHeight(pos);

  @override
  bool movementAllowed(BState state, Pos pos) =>
      BlockMovementChecks.isMovementAllowed(state, _hostLevel, pos);

  @override
  bool isBrittle(BState state) => BlockMovementChecks.isBrittle(state, _hostLevel);

  @override
  bool isBlockAttachedTowards(BState state, Pos pos, Direction direction) =>
      BlockMovementChecks.isBlockAttachedTowards(state, _hostLevel, pos, direction);

  @override
  bool isNotSupportive(BState state, Direction direction) =>
      BlockMovementChecks.isNotSupportive(state, direction, _hostLevel);

  @override
  PushReaction pushReaction(BState state) => _hostLevel.pushReaction(state);

  @override
  bool canStickTo(BState a, BState b) => SimServices.instance.canStickTo(a, b);

  @override
  List<Pos> additionalBlocks(BState state, Pos pos) => const [];

  @override
  List<SimGlueBox> superGluesIn(Aabb area) => [
    for (final glue in _hostLevel.gluesIn(area)) SimGlueBox(glue.id, glue.box),
  ];

  /// The honey glue volumes of the world, as the assembly sees them.
  ///
  /// `SimAssemblyContraption.checkAndCacheGlue` asks for the honey glue boxes
  /// whose box intersects a span, exactly as Java asks the level for
  /// `HoneyGlueEntity`s (`level.getEntitiesOfClass(HoneyGlueEntity.class,
  /// SuperGlueEntity.span(...).inflate(honeyGlueRange))`).
  ///
  /// The source is the entities themselves, not [HoneyGlueTracker]: the tracker
  /// is only written by the spawn and resize packets, so a volume that was saved
  /// with the chunk and loaded again (or one spawned by another path) is not in
  /// it, and a tracker-only read drops honey glue out of every assembly after a
  /// restart. The box is the entity's spawn data (`writeSpawnData`), which is
  /// saved with the entity (`PluginEntity.spawn_data` in `write_custom_nbt`).
  @override
  List<HoneyGlueVolume> honeyGluesIn(Aabb area) {
    // A honey glue entity's hitbox is 0.1 blocks at the bottom centre of its
    // volume, so the query box grows by the largest volume the config allows
    // before the decoded boxes are tested against [area]. The host's box query
    // scans every entity anyway (`entity_snapshots_in_box`), so the inflation
    // costs nothing.
    final range = SimConfigService.serverConfig.assembly.honeyGlueRange.toDouble();
    final volumes = <HoneyGlueVolume>[];
    for (final snapshot in world.getEntitiesInBox(
      min: (area.minX - range, area.minY - range, area.minZ - range),
      max: (area.maxX + range, area.maxY + range, area.maxZ + range),
      filter: const EntityFilterAll(),
    )) {
      if (snapshot.entityTypeKey != honeyGlueEntityKey) continue;
      final box = _honeyGlueBox(snapshot);
      if (box == null || !box.intersects(area)) continue;
      volumes.add(HoneyGlueVolume(snapshot.id, box));
    }
    return volumes;
  }

  /// The box of the honey glue volume behind [snapshot], `null` when that entity
  /// is gone or is not a honey glue.
  ///
  /// The snapshot carries no spawn data, so the entity is opened once per
  /// candidate; its hitbox is only the fallback for a volume saved without one.
  Aabb? _honeyGlueBox(EntitySnapshot snapshot) {
    final entity = world.getEntityById(id: snapshot.id);
    if (entity == null) return null;
    try {
      if (entity.pluginTypeKey != honeyGlueEntityKey) return null;
      final box = honeyGlueBoxFromSpawnData(entity.pluginSpawnData);
      if (box != null) return box;
    } finally {
      entity.dispose();
    }
    final bb = snapshot.boundingBox;
    return Aabb(bb.min.$1, bb.min.$2, bb.min.$3, bb.max.$1, bb.max.$2, bb.max.$3);
  }

  @override
  bool isSwivelBearing(BState state) => state.key == 'simulated:swivel_bearing';

  @override
  void superGlueMoved(SimGlueBox glue, Pos offset) {
    _hostLevel.addGlue(
      glue.box.move(offset.$1.toDouble(), offset.$2.toDouble(), offset.$3.toDouble()),
    );
  }

  /// `SimAssemblyHelper.assembleFromSingleBlock`'s honey-glue move: Java removes
  /// the volume's entity and spawns a new one at the moved box
  /// (`glue.remove(KILLED)` + `new HoneyGlueEntity(level, newBB)` +
  /// `setBoundsAndSync`).
  ///
  /// The host cannot spawn a *plugin* entity synchronously (the spawn is async),
  /// so the same entity keeps its id and is moved instead: its position goes to
  /// the bottom centre of the new box (`resetPositionToBounds`) and its spawn
  /// data -- the box the client draws and the thing saved with the chunk -- is
  /// replaced. The tracker is kept in step so the resize packet still finds the
  /// volume under the same id.
  @override
  void honeyGlueMoved(HoneyGlueVolume glue, Pos offset) {
    final box = glue.box.move(offset.$1.toDouble(), offset.$2.toDouble(), offset.$3.toDouble());
    honeyGlueTrackerOf(world.getId()).put(HoneyGlue(glue.id, box));

    final entity = world.getEntityById(id: glue.id);
    if (entity == null) return;
    try {
      if (entity.pluginTypeKey != honeyGlueEntityKey) return;
      final position = HoneyGlueVolumeLogic.positionForBounds(box);
      entity.setSpawnData(honeyGlueSpawnData(box, position));
      entity.setPositionRotationDelta(
        pos: position,
        yaw: entity.getYaw(),
        pitch: entity.getPitch(),
        velocity: entity.getVelocity(),
      );
    } finally {
      entity.dispose();
    }
  }

  @override
  void playDisassemblySound(Pos pos) =>
      ignoredSound(world, pos, 'simulated:block.physics_assembler.disassemble');

  @override
  void notifyChainConveyor(Pos pos) {}

  void ignoredSound(World world, Pos pos, String key) {}
}

/// The entities of a world, as the disassembly sees them.
final class PumpkinSimAssemblyEntities implements SimAssemblyEntities {
  PumpkinSimAssemblyEntities(this._world);

  /// The world id and a handle that survives its callback (see `WorldRef`).
  final WorldRef _world;

  /// A handle that is valid right now.
  World get world => _world.world;

  /// HOST GAP: the plugin API has no "entities in a box" query, only
  /// `World.getEntities()`, so this filters that list. It is called once per
  /// disassembly, not per tick.
  ///
  /// The filter and the ref both use the entity's real bounding box, not its
  /// position: a boat or a horse can straddle the edge of the assembly without
  /// its centre being inside it, and `moveOtherStuff` reads the box to decide
  /// whether the entity stands on a moved block. Aeronautics'
  /// `HostPropellerPushWorld` is the same filter with a different payload; both
  /// switch to the box query together when the host grows one.
  /// The entities the last [entitiesIn] returned, by id.
  final Map<int, Entity> _found = {};

  @override
  List<SimAssemblyEntityRef> entitiesIn(Aabb area) {
    _found.clear();
    final out = <SimAssemblyEntityRef>[];
    for (final entity in world.getEntities()) {
      final type = entity.pluginTypeKey;
      final isHoneyGlue = type == honeyGlueEntityKey;
      final bounds = entity.getBoundingBox();
      final box = Aabb(
        bounds.min.$1,
        bounds.min.$2,
        bounds.min.$3,
        bounds.max.$1,
        bounds.max.$2,
        bounds.max.$3,
      );
      // A honey glue's hitbox is 0.1 blocks at the bottom centre of its volume;
      // the box that matters is the spawn data, as `_moveEntities` reads it.
      final glueBox = isHoneyGlue
          ? honeyGlueBoxFromSpawnData(entity.pluginSpawnData)
          : null;
      if (!(glueBox ?? box).intersects(area)) continue;
      _found[entity.getId()] = entity;
      final pos = entity.getPosition();
      out.add(
        SimAssemblyEntityRef(
          entity.getId(),
          glueBox ?? box,
          (pos.$1, pos.$2, pos.$3),
          yRot: entity.getYaw(),
          kind: isHoneyGlue
              ? SimAssemblyEntityKind.honeyGlue
              : SimAssemblyEntityKind.other,
        ),
      );
    }
    return out;
  }

  /// `entity.remove(KILLED)`: a glue volume is replaced by a fresh one at the
  /// moved position, so the old one goes away.
  @override
  void remove(SimAssemblyEntityRef entity) {
    _found.remove(entity.id)?.remove();
  }

  /// `entity.setPos(...)` plus the y rotation of the structure transform.
  ///
  /// The velocity is carried through unchanged: a disassembly moves the entity
  /// without stopping it.
  @override
  void move(SimAssemblyEntityRef entity, (double, double, double) position, double yRot) {
    final handle = _found[entity.id];
    if (handle == null) return;
    handle.setPositionRotationDelta(
      pos: position,
      yaw: yRot,
      pitch: handle.getPitch(),
      velocity: handle.getVelocity(),
    );
  }

  /// `level.addFreshEntity(new SuperGlueEntity(level, box))`.
  ///
  /// HOST GAP: a plugin can spawn an entity of a *plugin* type, but
  /// `minecraft:glow_item_frame`-style vanilla glue boxes are Create's entity
  /// and the plugin API cannot summon a vanilla type with its own NBT. The
  /// assembly moves the glue's blocks; the box is dropped with it.
  @override
  void spawnSuperGlue(Aabb box) {}

  /// `level.addFreshEntity(new HoneyGlueEntity(level, box))`, then
  /// `setBoundsAndSync`.
  ///
  /// The spawn is async, so the entity is requested and the tracker entry is
  /// written when the host hands out its id. The tracker alone is not enough:
  /// the volume has to exist as an entity for the assembly's
  /// [PumpkinSimAssemblyWorld.honeyGluesIn] to find it again, and for the
  /// client to draw it.
  @override
  void spawnHoneyGlue(Aabb box) {
    final worldId = world.getId();
    final position = HoneyGlueVolumeLogic.positionForBounds(box);
    ignoredCall(
      world
          .spawnPlugin(
            honeyGlueEntityKey,
            position,
            spawnData: honeyGlueSpawnData(box, position),
          )
          .then((entity) {
            final id = entity.getId();
            entity.dispose();
            honeyGlueTrackerOf(worldId).put(HoneyGlue(id, box));
          }),
    );
  }
}

/// The installed host of Simulated.
final class PumpkinSimulatedHost implements SimulatedHost {
  PumpkinSimulatedHost(this.worlds, this.blockEntities, this.log);

  final Worlds worlds;
  final BlockEntityStore blockEntities;
  final Logger log;

  final Map<String, PumpkinSableLevel> _levels = {};
  final Map<String, PumpkinSimAssemblyWorld> _assemblyWorlds = {};
  final Map<String, PumpkinSimAssemblyEntities> _entities = {};

  @override
  SableLevel? levelOf(String worldId) {
    final world = worlds.byId(worldId);
    if (world == null) return null;
    return _levels.putIfAbsent(worldId, () => PumpkinSableLevel(WorldRef(worlds, worldId, world)));
  }

  @override
  SimAssemblyWorld? assemblyWorldOf(String worldId) {
    final world = worlds.byId(worldId);
    if (world == null) return null;
    return _assemblyWorlds.putIfAbsent(
      worldId,
      () => PumpkinSimAssemblyWorld(WorldRef(worlds, worldId, world), blockEntities),
    );
  }

  @override
  SimAssemblyEntities entitiesOf(String worldId) {
    final world = worlds.byId(worldId);
    if (world == null) return const NoSimAssemblyEntities();
    return _entities.putIfAbsent(
      worldId,
      () => PumpkinSimAssemblyEntities(WorldRef(worlds, worldId, world)),
    );
  }

  @override
  SubLevel? containingSubLevel(String worldId, Pos pos) {
    final level = levelOf(worldId);
    if (level == null) return null;
    final container = SubLevelContainer.of(level);
    if (container == null) return null;
    return container.getPlot(pos.$1 >> 4, pos.$3 >> 4)?.getSubLevel();
  }

  @override
  SubLevel? subLevelById(String worldId, String uniqueId) {
    final level = levelOf(worldId);
    if (level == null) return null;
    return SubLevelContainer.of(level)?.getSubLevelById(uniqueId);
  }

  @override
  void playSound(String worldId, Pos pos, String soundKey, {double volume = 1, double pitch = 1}) {
    final world = worlds.byId(worldId);
    if (world == null) return;
    final id = SimSoundIds.idOf(soundKey);
    if (id == null) return;
    ignoredSound(world, pos, id, volume: volume, pitch: pitch);
  }

  @override
  int bestNeighbourSignal(String worldId, Pos pos) {
    // The signal is read from the world on the next tick by the block itself;
    // the plugin API's `getBestNeighborSignal` is asynchronous, and the callers
    // only need a cached value.
    return _signals[worldId] ?? 0;
  }

  final Map<String, int> _signals = {};

  /// Updates the cached neighbour signal of [worldId] (the plugin refreshes it
  /// from the world tick).
  void setNeighbourSignal(String worldId, int signal) => _signals[worldId] = signal;

  @override
  bool isLoaded(String worldId, Pos pos) => worlds.byId(worldId)?.isLoaded(pos: pos.toBlockPos()) ?? false;

  @override
  String blockKeyAt(String worldId, Pos pos) {
    final world = worlds.byId(worldId);
    if (world == null) return 'minecraft:air';
    return _blockKeyOf(world.getBlockStateId(pos: pos.toBlockPos()));
  }

  @override
  void setBlock(String worldId, Pos pos, String blockKey) {
    final world = worlds.byId(worldId);
    if (world == null) return;
    final stateId = BlockRegistry.resolveState(blockKey, const {});
    if (stateId == null) return;
    world
        .setBlockState(pos: pos.toBlockPos(), state: stateId, updateFlags: BlockUpdateFlags.normal)
        .catchError((Object e) {
      log.warn('Could not place $blockKey at $pos: $e');
    });
  }

  @override
  void destroyBlock(String worldId, Pos pos, {bool drop = true}) {
    setBlock(worldId, pos, 'minecraft:air');
  }

  @override
  @override
  T? blockEntityAt<T>(String worldId, Pos pos) {
    final entity = blockEntities.at(worldId, pos.toBlockPos());
    return entity is T ? entity as T : null;
  }

  @override
  String? blockEntityTypeAt(String worldId, Pos pos) => blockEntities.at(worldId, pos.toBlockPos())?.typeKey;

  @override
  int gameTime(String worldId) => worlds.byId(worldId)?.worldAge ?? 0;

  @override
  void blockBreakParticles(String worldId, Pos pos, String blockKey) {}

  @override
  void sendStatusMessage(String playerId, String translationKey, List<Object?> args) {}
}

/// The key of a block state, from the host's registry.
String _blockKeyOf(int stateId) {
  final info = BlockStates.info(stateId);
  return info?.key ?? 'minecraft:air';
}

/// The ids of the sound events, filled by the plugin after registration.
abstract final class SimSoundIds {
  static final Map<String, int> _ids = {};

  static void put(String key, int id) => _ids[key] = id;

  static int? idOf(String key) => _ids[key];
}

void ignoredSound(World world, Pos pos, int id, {double volume = 1, double pitch = 1}) {}

/// The config of the assembler, read once per world tick.
int simMaxBlocksMoved() => SimConfigService.instance.server.assembly.maxBlocksMoved;
