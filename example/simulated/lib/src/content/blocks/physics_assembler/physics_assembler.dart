// The physics assembler: the block that turns a structure into a sub-level and
// back again.
//
// The block entity owns a [PhysicsAssemblerLogic] (the lever animation and the
// alignment timer) and drives the two assembly operations through
// `SimAssemblyHelper`. Everything that touches the world goes through the
// installed [SimulatedHost], so this class is safe to construct in a test.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.physics_assembler.PhysicsAssemblerBlockEntity
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart';

import '../../../config/sim_config_service.dart';
import '../../../host/simulated_host.dart';
import '../../../util/assembly/sim_assembly_exception.dart';
import '../../../util/sim_assembly_events.dart';
import '../../../util/sim_assembly_helper.dart';
import '../../../util/sim_level_util.dart';
import 'disassembly_prevention.dart';
import 'physics_assembler_logic.dart';

/// The state of one physics assembler.
///
/// Java: `PhysicsAssemblerBlockEntity` without the `SmartBlockEntity` half
final class PhysicsAssembler {
  PhysicsAssembler({required this.worldId, required this.pos, required this.state});

  /// The world the assembler is in.
  final String worldId;

  /// The block position.
  final Pos pos;

  /// The block state.
  BState state;

  /// The lever and disassembly state.
  final PhysicsAssemblerLogic logic = PhysicsAssemblerLogic();

  /// The sub-level this assembler assembled, if it is the primary one.
  String? assembledSubLevelId;

  /// The sticky face of the block: the direction the structure is on.
  Direction get stickyFacing {
    final face = state['face'];
    if (face == 'floor') return Direction.down;
    if (face == 'ceiling') return Direction.up;
    return (state.dir('facing') ?? Direction.north).opposite;
  }

  /// The position the structure is assembled from.
  Pos get assembleTarget => (
    pos.$1 + stickyFacing.stepX,
    pos.$2 + stickyFacing.stepY,
    pos.$3 + stickyFacing.stepZ,
  );

  /// `initialize()`.
  void initialize() {
    final host = simulatedHost;
    final subLevel = host.containingSubLevel(worldId, pos);
    logic.initializeLeverPosition(onSubLevel: subLevel != null);

    if (logic.primaryAssembler && subLevel != null && subLevel.uniqueIdOrNull != null) {
      final id = subLevel.uniqueIdOrNull!;
      if (DisassemblyPrevention.primaryAssemblerOf(id) == null) {
        DisassemblyPrevention.setPrimary(id, pos);
        assembledSubLevelId = id;
      }
    } else {
      logic.primaryAssembler = false;
    }
  }

  /// `tick()`.
  void tick() {
    logic.tickLever();

    if (logic.disassembling) {
      _tickDisassembly();
    }
  }

  void _tickDisassembly() {
    final host = simulatedHost;
    final level = host.levelOf(worldId);
    final subLevel = host.containingSubLevel(worldId, pos);
    if (level == null || subLevel is! ServerSubLevel) {
      logic.stopDisassembling();
      return;
    }

    final pose = subLevel.logicalPose;
    final orientation = logic.disassemblyOrientation;
    if (orientation == null) {
      logic.stopDisassembling();
      return;
    }

    final rotationPoint = pose.rotationPoint();
    final current = pose.transformPosition(
      Vector3d(rotationPoint.x.floorToDouble() + 0.5, rotationPoint.y.floorToDouble() + 0.5, rotationPoint.z.floorToDouble() + 0.5),
    );
    final goal = Vector3d(current.x.floorToDouble() + 0.5, current.y.floorToDouble() + 0.5, current.z.floorToDouble() + 0.5);

    final angle = Quaterniond.copy(pose.orientation()).div(orientation, Quaterniond()).angle();

    if (logic.tickDisassemblingWith(angleError: angle, distanceToGoal: current.distance(goal))) {
      placeIntoWorld(level, subLevel);
    }
  }

  /// `placeIntoWorld()`: the alignment converged, so put the blocks back.
  void placeIntoWorld(SableLevel level, ServerSubLevel subLevel) {
    final host = simulatedHost;
    try {
      throwDisassemblyExceptions(subLevel);
    } on SimAssemblyException catch (e) {
      logic.lastException = e;
      logic.stopDisassembling();
      return;
    }

    final world = host.assemblyWorldOf(worldId);
    if (world == null) {
      logic.stopDisassembling();
      return;
    }

    final goal = Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    final transformed = subLevel.logicalPose.transformPosition(goal);
    final goalPos = (transformed.x.floor(), transformed.y.floor(), transformed.z.floor());

    SimAssemblyHelper.disassembleSubLevel(
      world,
      level,
      subLevel,
      pos,
      goalPos,
      SimAssemblyHelper.rotationFrom90DegRots(logic.disassemblyAngle),
      entities: host.entitiesOf(worldId),
      playSound: true,
    );
    logic.stopDisassembling();
  }

  /// `throwDisassemblyExceptions(subLevel)`.
  void throwDisassemblyExceptions(ServerSubLevel subLevel) {
    final host = simulatedHost;
    final level = host.levelOf(worldId);
    if (level == null) return;

    final bounds = subLevel.boundingBox;
    final linear = Vector3d();
    final angular = Vector3d();
    final handle = subLevel.physicsBody;
    if (handle != null) {
      handle.getLinearVelocity(linear);
      handle.getAngularVelocity(angular);
    }

    logic.checkDisassemblyAllowed(
      bounds: bounds,
      minY: level.minY,
      maxY: level.maxY,
      linearVelocity: linear,
      angularVelocity: angular,
      hasTerrainNearby: _hasTerrainNearby(bounds, level),
    );
  }

  /// `assembleOrDisassemble()`.
  void assembleOrDisassemble() {
    final host = simulatedHost;
    final subLevel = host.containingSubLevel(worldId, pos);

    logic.flickLeverTo(subLevel == null);

    if (subLevel is ServerSubLevel) {
      final config = SimConfigService.instance.server.assembly;
      DisassemblyPrevention.checkSubLevelForPrimary(
        primaryDisassembly: config.primaryDisassembly,
        containingSubLevelId: subLevel.uniqueIdOrNull,
        toCheck: pos,
      );
      throwDisassemblyExceptions(subLevel);
      logic.startDisassembling(subLevel.logicalPose.orientation());
      return;
    }

    logic.primaryAssembler = true;
    final world = host.assemblyWorldOf(worldId);
    final level = host.levelOf(worldId);
    if (world == null || level == null) {
      logic.primaryAssembler = false;
      return;
    }

    try {
      final result = SimAssemblyHelper.assembleFromSingleBlock(world, level, pos, assembleTarget);
      logic.lastException = null;

      final id = result?.subLevel.uniqueIdOrNull;
      if (id != null) {
        assembledSubLevelId = id;
        DisassemblyPrevention.setPrimary(id, pos);
      }
      host.playSound(worldId, pos, 'simulated:block.physics_assembler.assemble');
      if (result != null) {
        SimAssemblyEvents.notifyAssembled(worldId, pos, result);
      }
    } on SimAssemblyException catch (e) {
      logic.primaryAssembler = false;
      assemblyFailed(e);
    }
  }

  /// `assemblyFailed(exception)`.
  void assemblyFailed(SimAssemblyException exception) {
    logic.lastException = exception;
  }

  /// `setClientHoldLeverInPlace(holding)`.
  void setClientHoldLeverInPlace(bool holding) => logic.holdingLever = holding;

  /// `updateControlledByPlayer(angle)`.
  void updateControlledByPlayer(double angle) => logic.updateControlledByPlayer(angle);

  /// `stopControllingPlayer()`.
  bool stopControllingPlayer() => logic.stopControllingPlayer();

  /// `getClientAngle(partialTicks)`.
  double clientAngle([double partialTicks = 1]) => logic.visualAngle.getValue(partialTicks);

  /// `remove()`: a primary assembler forgets that it was one.
  void removed() {
    if (logic.primaryAssembler) {
      final id = assembledSubLevelId;
      if (id != null) DisassemblyPrevention.setPrimary(id, null);
    }
    logic.stopDisassembling();
  }

  /// The saved data (`write`).
  Map<String, Object?> write() => {
    'IsPrimary': logic.primaryAssembler,
    if (logic.lastException != null) 'LastException': logic.lastException!.translationKey,
    if (assembledSubLevelId != null) 'SubLevel': assembledSubLevelId,
  };

  /// `read`.
  void read(Map<String, Object?> tag) {
    logic.primaryAssembler = tag['IsPrimary'] == true;
    final key = tag['LastException'];
    logic.lastException = key is String ? SimAssemblyException(key) : null;
    final id = tag['SubLevel'];
    assembledSubLevelId = id is String ? id : null;
  }

  /// The mid-air scan: whether any section within one chunk of the bounds has a
  /// non-air block.
  bool _hasTerrainNearby(BoundingBox3dc bounds, SableLevel level) {
    final host = simulatedHost;
    final minChunkX = (bounds.minX.floor() >> 4) - 1;
    final minChunkY = (bounds.minY.floor() >> 4) - 1;
    final minChunkZ = (bounds.minZ.floor() >> 4) - 1;
    final maxChunkX = (bounds.maxX.floor() >> 4) + 1;
    final maxChunkY = (bounds.maxY.floor() >> 4) + 1;
    final maxChunkZ = (bounds.maxZ.floor() >> 4) + 1;

    for (var x = minChunkX; x <= maxChunkX; x++) {
      for (var z = minChunkZ; z <= maxChunkZ; z++) {
        for (var y = minChunkY; y <= maxChunkY; y++) {
          final pos = (x << 4, y << 4, z << 4);
          if (!SimLevelUtil.isAreaActuallyLoaded(level, pos, 16)) continue;
          if (host.blockKeyAt(worldId, pos) != 'minecraft:air') return true;
        }
      }
    }
    return false;
  }
}
