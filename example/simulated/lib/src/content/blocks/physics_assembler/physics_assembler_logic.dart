// The state machine of the physics assembler, kept apart from the block entity so
// it runs on the VM in tests: the lever animation, the disassembly alignment
// timer and the checks that decide whether a sub-level may be placed back.
//
// The block entity (`physics_assembler_block_entity.dart`) owns an instance and
// forwards its lifecycle to it; everything here is pure.
//
// Java: dev.simulated_team.simulated.content.blocks.physics_assembler.PhysicsAssemblerBlockEntity
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:create/src/api/lerped_float.dart';
import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart';

import '../../../config/sim_config_service.dart';
import '../../../util/assembly/sim_assembly_exception.dart';
import '../../../util/sim_math_utils.dart';

/// The lever animation and disassembly progress of one assembler.
///
/// Java: the state fields of `PhysicsAssemblerBlockEntity`
final class PhysicsAssemblerLogic {
  /// The angle the lever rests at when flicked, in degrees.
  static const double flickedAngleDegrees = 45;

  /// How fast the lever chases its target (`LerpedFloat.Chaser.EXP`).
  static const double leverChaseSpeed = 0.75;

  /// Stiffness of the linear alignment motors.
  static const double linearStiffness = 1000;

  /// Damping of the linear alignment motors.
  static const double linearDamping = 50;

  /// Stiffness of the angular alignment motors.
  static const double angularStiffness = 13000;

  /// Damping of the angular alignment motors.
  static const double angularDamping = 1000;

  /// The visual lever angle.
  final LerpedFloat visualAngle = LerpedFloat.linear();

  /// The last assembly failure, or `null`.
  SimAssemblyException? lastException;

  /// Whether this assembler assembled the sub-level it stands on.
  bool primaryAssembler = false;

  /// Whether the lever is held by the player until an answer arrives.
  bool holdingLever = false;

  bool leverInitialized = false;
  bool disassembling = false;
  int disassemblingTicks = 0;
  int disassemblyReadyTicks = 0;
  int disassemblyAngle = 0;
  Quaterniond? disassemblyOrientation;

  bool controlledByPlayer = false;
  double playerAngle = 0;

  /// `initializeLeverPosition`: flick the lever to match the state.
  void initializeLeverPosition({required bool onSubLevel}) {
    if (leverInitialized) return;
    flickLeverTo(onSubLevel);
    jerkLever();
    leverInitialized = true;
  }

  /// The lever half of `tick()`. The disassembly half is
  /// [tickDisassemblingWith], because it needs the sub-level's pose.
  void tickLever() {
    if (holdingLever) {
      // The lever stays where it is until the assembly answers.
      visualAngle.value = visualAngle.value;
    } else if (controlledByPlayer) {
      visualAngle.value = visualAngle.value;
      visualAngle.previousValue = playerAngle;
    } else {
      visualAngle.tickChaser();
    }
  }

  /// The maximum number of ticks the alignment may take.
  int get maxDisassemblyTicks => SimConfigService.instance.server.assembly.maxDisassemblyTicks * 5;

  /// One tick of the alignment; returns true when the sub-level should be placed
  /// into the world.
  ///
  /// [angleError] is the angle between the sub-level and its disassembly
  /// orientation, in radians; [distanceToGoal] the distance of its rotation point
  /// from the snapped goal.
  bool tickDisassemblingWith({
    required double angleError,
    required double distanceToGoal,
  }) {
    disassemblingTicks++;

    if (disassemblingTicks >= maxDisassemblyTicks) {
      lastException = SimAssemblyException.couldNotAlign();
      stopDisassembling();
      return false;
    }

    final config = SimConfigService.instance.server.assembly;
    final withinTolerance = angleError.abs() * 180 / math.pi <= config.disassemblyDegreeTolerance &&
        distanceToGoal < 0.2;

    if (withinTolerance) {
      disassemblyReadyTicks++;
    } else {
      disassemblyReadyTicks = 0;
    }

    if (disassemblyReadyTicks > 5) {
      return true;
    }
    return false;
  }

  /// `stopDisassembling()`: resets the alignment.
  void stopDisassembling() {
    disassemblingTicks = 0;
    disassemblyReadyTicks = 0;
    disassembling = false;
    disassemblyOrientation = null;
  }

  /// `clientFlickLeverTo(flicked)`.
  void flickLeverTo(bool flicked) {
    visualAngle.chase(flicked ? flickedAngleDegrees : 0, leverChaseSpeed, Chasers.exp);
  }

  /// `jerkLever()`: snap the lever to its chase target.
  void jerkLever() {
    visualAngle
      ..value = visualAngle.chaseTarget
      ..previousValue = visualAngle.chaseTarget;
  }

  /// `updateControlledByPlayer(angle)`.
  void updateControlledByPlayer(double angle) {
    controlledByPlayer = true;
    playerAngle = angle;
  }

  /// `stopControllingPlayer()`; true when the player was in control.
  bool stopControllingPlayer() {
    if (!controlledByPlayer) return false;
    controlledByPlayer = false;
    return true;
  }

  /// `startDisassembling`: picks the closest 90° turn for the placement and
  /// records the orientation the sub-level is aligned to.
  ///
  /// Returns the number of 90° turns (`disassemblyAngle`).
  int startDisassembling(Quaterniond orientation) {
    final closestYRotation = SimMathUtils.closestYaw(orientation);
    const ninety = math.pi / 2.0;
    final turns = -(closestYRotation / ninety + 0.5).floor();

    disassemblyAngle = turns;
    disassemblyOrientation = Quaterniond()..rotateY(turns * ninety);
    disassembling = true;
    disassemblingTicks = 0;
    disassemblyReadyTicks = 0;
    return turns;
  }

  /// `throwDisassemblyExceptions`: the checks before a sub-level is placed back.
  ///
  /// [bounds] are the sub-level's global bounds, [minY]/[maxY] the build height
  /// of the level, and [hasTerrainNearby] the result of the mid-air scan (only
  /// asked when `disallowMidAirDisassembly` is on).
  void checkDisassemblyAllowed({
    required BoundingBox3dc bounds,
    required int minY,
    required int maxY,
    required Vector3d linearVelocity,
    required Vector3d angularVelocity,
    required bool hasTerrainNearby,
  }) {
    final config = SimConfigService.instance.server.assembly;

    if (bounds.maxY > maxY || bounds.minY < minY) {
      throw SimAssemblyException.outOfWorld();
    }

    final maxLinear = config.disassemblyMaxVelocity;
    final maxAngular = config.disassemblyMaxAngularVelocity;
    if (linearVelocity.lengthSquared > maxLinear * maxLinear ||
        angularVelocity.lengthSquared > maxAngular * maxAngular) {
      throw SimAssemblyException.tooFast();
    }

    if (config.disallowMidAirDisassembly && !hasTerrainNearby) {
      throw SimAssemblyException.tooFarFromGround();
    }
  }
}

/// The sticky face of an assembler: the direction the structure is assembled
/// from, given the block's `face` and `facing` properties.
Direction stickyFacing(String? face, Direction facing) => switch (face) {
  'floor' => Direction.down,
  'ceiling' => Direction.up,
  _ => facing.opposite,
};
