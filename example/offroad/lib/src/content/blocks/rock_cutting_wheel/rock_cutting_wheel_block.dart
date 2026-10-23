// The rock cutting wheel: a block on a borehead contraption that tells its
// bearing where to cut.
//
// Java: `content/blocks/rock_cutting_wheel/{RockCuttingWheelBlock,
// RockCuttingWheelBlockEntity,RockCuttingWheelActor}`.
//
// The rotation maths (`reverseRotation`, `searchOrigin`) is pure and lives in
// `rock_cutting_wheel_rotation.dart`; this file is the block, the block entity
// and the actor.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' as math;

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/common.dart' show Pos, Vec3, vec3Zero;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/contraptions/core/level.dart' show ContraptionLevel;
import 'package:create/src/contraptions/core/movement.dart' show MovementBehaviour, MovementContext;
import 'package:create/src/contraptions/core/movement_checks.dart' show CheckResult;
import 'package:create/src/kinetics/wire_def.dart' show WireKineticDef;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show SubLevelHelper, Vector3d;

import '../../../host/offroad_hooks.dart';
import '../../../host/placement.dart' show applyDirectionalAxisPlacement;
import '../../../index/offroad_ids.dart';
import 'rock_cutting_wheel_rotation.dart';
import 'wheel_assembly_rules.dart';

/// The block and block entity key (`offroad:rockcutting_wheel`).
const String rockCuttingWheelKey = OffroadIds.rockCuttingWheel;

/// `RockCuttingWheelBlockEntity`: the client animation state of one wheel.
///
/// The server half is empty in Java (`addBehaviours` adds nothing and `tick`
/// only animates on the client), so this entity is not a kinetic one.
final class RockCuttingWheelBlockEntity extends CreateBlockEntity {
  RockCuttingWheelBlockEntity(super.worldId, super.pos);

  /// `LerpedFloat.angular()`: the angle the model is drawn at.
  double angle = 0;

  /// `manuallyAnimatedSpeed`.
  double manuallyAnimatedSpeed = 0;

  /// `maxDuration` / `duration`: how long the animation runs.
  int maxDuration = 0;
  int duration = 0;

  /// `getAnimatedSpeed(partialTicks)`.
  double getAnimatedSpeed(double partialTicks) => angle;

  /// `setAnimatedSpeed(speed)`.
  void setAnimatedSpeed(double speed) => manuallyAnimatedSpeed = speed;

  /// `setMaxDuration(duration)`.
  void setMaxDuration(int value) {
    maxDuration = value;
    duration = 0;
  }

  /// `tick`'s virtual branch (a ponder): the wheel spins by itself for
  /// [maxDuration] ticks.
  void tickVirtual() {
    if (duration + 2 > maxDuration) {
      manuallyAnimatedSpeed = 0;
    } else {
      duration++;
    }
    angle = _lerpExp(angle, angle + manuallyAnimatedSpeed, 1);
  }

  static double _lerpExp(double from, double to, double delta) =>
      from + (to - from) * (1 - math.exp(-delta * 3));
}

/// `RockCuttingWheelBlock`.
CreateBlock buildRockCuttingWheelBlock() => CreateBlock(
  key: rockCuttingWheelKey,
  properties: [CreateProps.facing, BlockProperty.boolean('axis_along_first')],
  defaultState: {'facing': 'north'},
  // `SharedProperties.softMetal()`: `Blocks.GOLD_BLOCK`'s 3 / 6.
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  // `getFacingForPlacement` is `context.getClickedFace()`; `axis_along_first` needs the
  // clicked face's axis *and* the player's look, which no `PlacementRule` source can
  // combine, so it is applied in `onPlaced` (see `host/placement.dart`).
  placement: const [PlacementRule.clickedFace('facing')],
  blockEntityType: rockCuttingWheelKey,
  behavior: BlockBehavior(
    onPlaced: (server, e) => applyDirectionalAxisPlacement(server, e),
  ),
);

/// `RockCuttingWheelBlock`'s static block (`RockCuttingWheelBlock.java:12-23`): a wheel
/// attaches towards every direction except its own face.
///
/// A contraption captures the neighbour a wheel points at only when that neighbour is
/// itself attached towards the wheel; the wheel is not, so its face stops the search and
/// a contraption does not swallow the blocks in front of it through the wheel.
CheckResult rockCuttingWheelAttachedCheck(
  BState state,
  ContraptionLevel level,
  Pos pos,
  Direction direction,
) {
  if (!isRockCuttingWheel(state)) return CheckResult.pass;
  return CheckResult.of(!rockCuttingWheelFacesDirection(state, direction));
}

/// `RockCuttingWheelBlock`'s static block (`RockCuttingWheelBlock.java:25-31`): the
/// wheel does not support what is in front of it.
CheckResult rockCuttingWheelNotSupportiveCheck(BState state, Direction direction) {
  if (!isRockCuttingWheel(state)) return CheckResult.pass;
  return rockCuttingWheelFacesDirection(state, direction) ? CheckResult.fail : CheckResult.pass;
}

/// `AbstractDirectionalAxisBlock`: `facing` + `axis_along_first`, the shaft on
/// the rotation axis those two give (`DirectionalAxisKineticBlock`).
final WireKineticDef rockCuttingWheelKineticDef = WireKineticDef.perpendicularToFacing();

/// `RockCuttingWheelActor`: tells the bearing of the contraption where this
/// wheel sits and how fast it turns.
final class RockCuttingWheelActor extends MovementBehaviour {
  const RockCuttingWheelActor();

  @override
  bool breaksBlocks() => true;

  @override
  bool? passesThroughCollision(level, colliderPos, collidedState) => false;

  @override
  Future<void> tick(MovementContext context) async {
    final controller = OffroadHooks.controllerOf(context.contraption);
    if (controller == null) return;

    final meetsSpeed = controller.speed.abs() > 0.1;

    if (!context.data.contains('Initialized')) {
      final index = controller.requestNewIndexAndIncrement(isRockCuttingWheel: true);
      if (index != -1) context.data.putInt('Index', index);
      context.data.putBool('Initialized', true);
    }

    if (!meetsSpeed || controller.isStalled) return;

    final facing = context.state.dir('facing') ?? Direction.north;
    final origin = RockCuttingWheelRotation.searchOrigin(context.localPos, facing);

    // `contraption.entity.toGlobalVector(centerPos, 1)` in Java: the port's
    // `context.position` is already the world position of the actor, so only the
    // offset from the block centre to the search origin has to be rotated.
    final centre = context.position!;
    final offset = (
      origin.$1 - context.localPos.$1 - 0.5,
      origin.$2 - context.localPos.$2 - 0.5,
      origin.$3 - context.localPos.$3 - 0.5,
    );
    final level = OffroadHooks.sableLevelOf(context.worldId);
    if (level == null) return;

    final rotated = context.rotation(offset);
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(centre.$1 + rotated.$1, centre.$2 + rotated.$2, centre.$3 + rotated.$3),
    );

    controller.updatePosition(context.data.getInt('Index'), (projected.x, projected.y, projected.z));
  }
}

/// The `Vec3` of a [BState]'s facing, for the actor's search origin.
Vec3 facingStep(BState state) {
  final facing = state.dir('facing') ?? Direction.north;
  return (facing.stepX.toDouble(), facing.stepY.toDouble(), facing.stepZ.toDouble());
}

/// The position of a wheel on a contraption, for the tests.
Pos wheelLocalPos(MovementContext context) => context.localPos;

/// `vec3Zero` is the empty mining origin the bearing starts from.
const Vec3 emptyMiningOrigin = vec3Zero;
