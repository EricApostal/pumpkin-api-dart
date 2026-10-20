// The Create machines whose lookups reach across sub-levels: fluid handling,
// boilers, chutes, the mechanical arm, the lectern controller, the deployer and
// the ejector.
//
// Each function is the pure part of one Java compat mixin: where the machine
// searches for a block, a block entity or a fluid, the search runs on every
// position the queried location can mean. The host supplies the lookups
// (`hasBlock`, `blockEntityAt`, `hasFluid`), so this file needs neither the
// Create block entity classes nor a level implementation.
//
// Pure: no host imports.
//
// Java: `...create.fluid_handling.OpenEndedPipeMixin`,
// `...create.fluid_tank_heating.BoilerDataMixin`,
// `...create.hose_pulley.HosePulleyBlockEntityMixin`,
// `...create.hose_pulley.HosePulleyFluidHandlerMixin`,
// `...create.inventory_manipulation.ChuteBlockEntityMixin`,
// `...create.inventory_manipulation.CapManipulationBehaviourBaseMixin`,
// `...create.mechnical_arm.MechanicalArmBlockEntity`,
// `...create.lectern_controller.LecternControllerBlockEntityMixin`,
// `...create.deployer.DeployerBlockEntityMixin`,
// `...create.ejector.EjectorBlockEntityMixin`,
// `...create.basin_interactions.BasinBlockEntityMixin`,
// `...create.basin_interactions.BasinOperatingBlockEntityMixin`,
// `...create.saw.SawBlockEntityMixin`, `...create.nozzle.block_entity.*`,
// `...create.redstone_contacts.RedstoneContactBlockMixin`.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/api/sub_level_helper.dart';
import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/sub_level.dart';
import 'create_behaviours.dart';

/// The lookups a machine search needs from the host.
typedef BlockStateLookup = String? Function(Pos pos);
typedef BlockEntityLookup = Object? Function(Pos pos);

/// `runIncludingSubLevels` for a block position: the origin, its projection out
/// of its sub-level and every sub-level overlapping the projection.
abstract final class SubLevelSearch {
  /// Runs [converter] on each candidate position; the first non-`null` result
  /// wins.
  ///
  /// [origin] is a plot-space position (the space the machine's own block is
  /// in), [containing] its sub-level.
  static T? at<T>(
    SableLevel level,
    Pos origin,
    SubLevel? containing,
    T? Function(SubLevel? subLevel, Pos pos) converter, {
    bool shouldCheckOrigin = true,
  }) => SubLevelHelper.runIncludingSubLevels<T>(
    level,
    Vector3d(origin.$1 + 0.5, origin.$2 + 0.5, origin.$3 + 0.5),
    shouldCheckOrigin,
    containing,
    converter,
  );

  /// `runIncludingSubLevels` over the *centre* of [origin], which is what the
  /// block entity lookups pass (`Vec3.atCenterOf`).
  static T? atCenter<T>(
    SableLevel level,
    Vec3 center,
    SubLevel? containing,
    T? Function(SubLevel? subLevel, Pos pos) converter, {
    bool shouldCheckOrigin = true,
  }) => SubLevelHelper.runIncludingSubLevels<T>(
    level,
    Vector3d(center.$1, center.$2, center.$3),
    shouldCheckOrigin,
    containing,
    converter,
  );
}

/// `OpenEndedPipeMixin`: an open pipe looks for a fluid source in the block in
/// front of it, wherever that block ends up.
///
/// [outputPos] is the pipe's output position and [hasFluid] the level's fluid
/// test. The result is the position to draw from and the state it holds, or
/// `null` when there is no fluid.
final class OpenEndedPipeLookup {
  /// `sable$getBlockstateInclSublevels`: the state the pipe acts on, and the
  /// position it belongs to.
  static ({Pos pos, String state})? findOutput(
    SableLevel level,
    Pos outputPos,
    SubLevel? containing,
    String? Function(Pos pos) stateAt,
  ) {
    final found = SubLevelSearch.at<({Pos pos, String state})>(level, outputPos, containing, (subLevel, pos) {
      final state = stateAt(pos);
      if (state == null) return null;
      // `BlockState.isAir()`: the pipe only cares about a block that is there.
      if (state == 'minecraft:air') return null;
      return (pos: pos, state: state);
    });

    if (found != null) return found;

    final fallback = stateAt(outputPos);
    return fallback == null ? null : (pos: outputPos, state: fallback);
  }
}

/// `BoilerDataMixin` / `BasinBlockEntityMixin`: the heat level of a heater under
/// a boiler or basin, found through sub-levels.
abstract final class HeaterLookup {
  /// The heat of the block below [pos], or [none] when no candidate is a heater.
  ///
  /// [heatOf] is `BoilerHeater.findHeat(level, pos, state)`: `-1` for "not a
  /// heater", any other value the heat.
  static double findHeat(
    SableLevel level,
    Pos boilerPos,
    SubLevel? containing,
    double Function(Pos pos) heatOf, {
    double none = -1,
  }) {
    // `getBlockPos().below()`: the heater is the block under the boiler.
    final pos = (boilerPos.$1, boilerPos.$2 - 1, boilerPos.$3);
    final found = SubLevelSearch.at<double>(level, pos, containing, (subLevel, candidate) {
      final heat = heatOf(candidate);
      return heat == none ? null : heat;
    }, shouldCheckOrigin: false);

    return found ?? none;
  }
}

/// `HosePulleyBlockEntityMixin`: whether the hose's next position is blocked.
abstract final class HosePulleyCheck {
  /// `sable$getBlockState`: the state at the hose's next position, or the
  /// original when no candidate matches.
  ///
  /// [inverseReplaceCheck] is `true` for the lazy tick (the hose wants a block it
  /// cannot replace, i.e. something solid to stop on) and `false` for the tick
  /// and the speed change (it wants a replaceable block, i.e. air or water).
  static String? nextState(
    SableLevel level,
    Pos checkPos,
    SubLevel? containing,
    String Function(Pos pos) stateAt,
    bool Function(String state) canBeReplaced, {
    required bool inverseReplaceCheck,
    required String original,
  }) {
    final found = SubLevelSearch.at<String>(level, checkPos, containing, (subLevel, pos) {
      final state = stateAt(pos);
      return (inverseReplaceCheck ^ canBeReplaced(state)) ? state : null;
    });

    return found ?? original;
  }
}

/// `HosePulleyFluidHandlerMixin`: the position a hose pulley drains from.
abstract final class HosePulleyDrain {
  /// `sable$subLevelDrainPos`: the position with fluid, kept within
  /// [leniency] blocks of the last valid one so the drain does not jump between
  /// sub-levels.
  static Pos drainPos(
    SableLevel level,
    Pos rootPos,
    SubLevel? containing,
    bool Function(Pos pos) hasFluid, {
    Pos? lastValidPos,
    double leniency = 1.5,
  }) {
    final found = SubLevelSearch.at<Pos>(level, rootPos, containing, (subLevel, pos) {
      if (!hasFluid(pos)) return null;

      if (lastValidPos == null) return pos;
      final dx = lastValidPos.$1 - pos.$1;
      final dy = lastValidPos.$2 - pos.$2;
      final dz = lastValidPos.$3 - pos.$3;
      // A jump larger than the leniency is a move between spaces; take the new
      // position, otherwise keep the old one so the drain stays put.
      return dx * dx + dy * dy + dz * dz > leniency * leniency ? pos : lastValidPos;
    });

    return found ?? rootPos;
  }
}

/// `ChuteBlockEntityMixin`: the direction a chute queries for a handler.
abstract final class ChuteLookup {
  /// `sable$grabCap`: the handler direction and position for a chute whose
  /// neighbour is on [side].
  ///
  /// The chute looks at the neighbour from the opposite side, and that direction
  /// is rotated out of the neighbour's sub-level: a chute on one ship facing a
  /// chest on another has to ask in the chest's frame.
  static ({Pos pos, Direction direction})? handlerAt(
    SableLevel level,
    Pos checkPos,
    SubLevel? parentSubLevel,
    Direction side,
    bool Function(Pos pos) hasHandler,
  ) {
    return SubLevelSearch.at<({Pos pos, Direction direction})>(
      level,
      checkPos,
      parentSubLevel,
      (subLevel, pos) {
        if (!hasHandler(pos)) return null;
        return (pos: pos, direction: ChuteDirection.resolve(side, subLevel?.logicalPose));
      },
      shouldCheckOrigin: false,
    );
  }
}

/// `CapManipulationBehaviourBaseMixin` / `MechanicalArmBlockEntity`: the block
/// entity a machine reaches for.
abstract final class CapabilityLookup {
  /// The position of the first candidate block entity that passes [filter], or
  /// `null`.
  static Pos? findBlockEntity(
    SableLevel level,
    Pos pos,
    SubLevel? containing,
    BlockEntityLookup blockEntityAt,
    bool Function(Object blockEntity) filter,
  ) => SubLevelSearch.at<Pos>(level, pos, containing, (subLevel, candidate) {
    final entity = blockEntityAt(candidate);
    return entity != null && filter(entity) ? candidate : null;
  });

  /// `MechanicalArmBlockEntity.isAreaActuallyLoaded`: an arm inside a sub-level
  /// always considers its area loaded (the plot chunks are ticketed).
  static bool isAreaLoaded(SableLevel level, Pos center) =>
      SubLevelHelper.getContaining(level, center) != null;
}

/// `LecternControllerBlockEntityMixin`: the distance check of the lectern
/// controller.
abstract final class LecternControllerRange {
  /// `sable$fixDistanceCheck`: whether the player is within [range] of the
  /// lectern, across sub-levels.
  static bool playerInRange(SableLevel level, Vec3 playerPosition, Vec3 lecternPosition, double range) =>
      SubLevelHelper.distanceSquaredWithSubLevels(
        level,
        Vector3d(playerPosition.$1, playerPosition.$2, playerPosition.$3),
        Vector3d(lecternPosition.$1, lecternPosition.$2, lecternPosition.$3),
      ) <
      range * range;
}

/// `RedstoneContactBlockMixin`: whether a redstone contact has a block in front
/// of it, wherever that block is.
abstract final class RedstoneContactLookup {
  /// The contact's front block position, projected out of its sub-level.
  static Pos frontInWorld(SableLevel level, Pos contactPos, Direction facing) {
    final projected = ProjectedBlockCenter.of(level, (
      contactPos.$1 + facing.stepX,
      contactPos.$2 + facing.stepY,
      contactPos.$3 + facing.stepZ,
    ));
    return (projected.$1.floor(), projected.$2.floor(), projected.$3.floor());
  }
}

/// The turntable / nozzle / funnel block centre, kept next to the other block
/// projections.
abstract final class ProjectedCenter {
  /// `VecHelper.getCenterOf(pos)` projected out of [level].
  static Vec3 of(SableLevel level, Pos pos) => ProjectedBlockCenter.of(level, pos);
}

/// `TurntableBlockMixin`'s y: the world y of a block's lower corner.
double projectedBlockY(SableLevel level, Pos pos) =>
    SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(pos.$1.toDouble(), pos.$2.toDouble(), pos.$3.toDouble()),
    ).y;

/// The axis a rotated vector points along, for the chute and nozzle lookups.
Axis dominantAxis(Vec3 vector) {
  final ax = vector.$1.abs();
  final ay = vector.$2.abs();
  final az = vector.$3.abs();
  if (ax >= ay && ax >= az) return Axis.x;
  if (ay >= ax && ay >= az) return Axis.y;
  return Axis.z;
}

/// The pose of a sub-level, `null` when there is none.
Pose3dc? poseOf(SubLevel? subLevel) => subLevel?.logicalPose;
