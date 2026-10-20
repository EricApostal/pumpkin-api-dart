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
import '../util/assembly/sim_assembly_contraption.dart';
import '../util/sim_assembly_helper.dart';
import 'simulated_host.dart';

/// A world as sable's sub-level model sees it.
final class PumpkinSableLevel implements SableLevel {
  PumpkinSableLevel(this.world);

  final World world;

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
  PumpkinSimAssemblyWorld(this.world, this.blockEntities)
    : _level = HostContraptionLevel(world, blockEntities, DefaultContraptionSettings());

  final World world;
  final BlockEntityStore blockEntities;
  final HostContraptionLevel _level;

  @override
  BState stateAt(Pos pos) => _level.stateAt(pos);

  @override
  bool isLoaded(Pos pos) => _level.isLoaded(pos);

  @override
  bool isOutsideBuildHeight(Pos pos) => _level.isOutsideBuildHeight(pos);

  @override
  bool movementAllowed(BState state, Pos pos) =>
      BlockMovementChecks.isMovementAllowed(state, _level, pos);

  @override
  bool isBrittle(BState state) => BlockMovementChecks.isBrittle(state, _level);

  @override
  bool isBlockAttachedTowards(BState state, Pos pos, Direction direction) =>
      BlockMovementChecks.isBlockAttachedTowards(state, _level, pos, direction);

  @override
  bool isNotSupportive(BState state, Direction direction) =>
      BlockMovementChecks.isNotSupportive(state, direction, _level);

  @override
  PushReaction pushReaction(BState state) => _level.pushReaction(state);

  @override
  bool canStickTo(BState a, BState b) => SimServices.instance.canStickTo(a, b);

  @override
  List<Pos> additionalBlocks(BState state, Pos pos) => const [];

  @override
  List<SimGlueBox> superGluesIn(Aabb area) => [
    for (final glue in _level.gluesIn(area)) SimGlueBox(glue.id, glue.box),
  ];

  /// HOST GAP: honey glue volumes are plugin entities; the plugin's tracker is
  /// the only source, and it is filled by the entity spawn and removal events.
  @override
  List<HoneyGlueVolume> honeyGluesIn(Aabb area) => const [];

  @override
  bool isSwivelBearing(BState state) => state.key == 'simulated:swivel_bearing';

  @override
  void superGlueMoved(SimGlueBox glue, Pos offset) {
    _level.addGlue(
      glue.box.move(offset.$1.toDouble(), offset.$2.toDouble(), offset.$3.toDouble()),
    );
  }

  @override
  void honeyGlueMoved(HoneyGlueVolume glue, Pos offset) {}

  @override
  void playDisassemblySound(Pos pos) =>
      ignoredSound(world, pos, 'simulated:block.physics_assembler.disassemble');

  @override
  void notifyChainConveyor(Pos pos) {}

  void ignoredSound(World world, Pos pos, String key) {}
}

/// The entities of a world, as the disassembly sees them.
final class PumpkinSimAssemblyEntities implements SimAssemblyEntities {
  PumpkinSimAssemblyEntities(this.world);

  final World world;

  /// HOST GAP: the plugin API has no "entities in a box" query, only
  /// `World.getEntities()`, so this filters that list. It is called once per
  /// disassembly, not per tick.
  @override
  List<SimAssemblyEntityRef> entitiesIn(Aabb area) {
    final out = <SimAssemblyEntityRef>[];
    for (final entity in world.getEntities()) {
      final pos = entity.getPosition();
      final x = pos.$1, y = pos.$2, z = pos.$3;
      if (x < area.minX || x > area.maxX || y < area.minY || y > area.maxY || z < area.minZ || z > area.maxZ) {
        continue;
      }
      out.add(
        SimAssemblyEntityRef(
          entity.getId(),
          Aabb(x - 0.5, y, z - 0.5, x + 0.5, y + 1, z + 0.5),
          (x, y, z),
        ),
      );
    }
    return out;
  }

  @override
  void remove(SimAssemblyEntityRef entity) {}

  @override
  void move(SimAssemblyEntityRef entity, (double, double, double) position, double yRot) {}

  @override
  void spawnSuperGlue(Aabb box) {}

  @override
  void spawnHoneyGlue(Aabb box) {}
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
    return _levels.putIfAbsent(worldId, () => PumpkinSableLevel(world));
  }

  @override
  SimAssemblyWorld? assemblyWorldOf(String worldId) {
    final world = worlds.byId(worldId);
    if (world == null) return null;
    return _assemblyWorlds.putIfAbsent(worldId, () => PumpkinSimAssemblyWorld(world, blockEntities));
  }

  @override
  SimAssemblyEntities entitiesOf(String worldId) {
    final world = worlds.byId(worldId);
    if (world == null) return const NoSimAssemblyEntities();
    return _entities.putIfAbsent(worldId, () => PumpkinSimAssemblyEntities(world));
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
