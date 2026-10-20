// The maths of a propeller bearing: the sails it finds in its contraption, the
// thrust and airflow they produce, and the rotation ramp-up.
//
// Java: `content/blocks/propeller/bearing/propeller_bearing/PropellerBearingBlockEntity`.
//
// The bearing is a mechanical bearing whose contraption is a propeller: the
// sails captured in the contraption become discs, and the bearing's rotation
// speed turns them into thrust. The Java block entity does this inline; the port
// keeps it here so the numbers can be tested without a world.
//
// Pure: no host imports (simulated's controller is a pure file too).
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show AxisDirection, Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/kinetics/settings.dart' show convertToAngular;
import 'package:simulated/src/api/bearing_slowdown_controller.dart'
    show BearingSlowdownController;
import 'package:sable/sable.dart' show Vector3d;

import '../config/aero_config.dart';
import 'propeller_actor_behaviour.dart';

/// `PropellerBearingBlockEntity.ThrustDirection`: which way the propeller
/// pushes at a given rotation direction.
enum ThrustDirection {
  /// Pulls when turning clockwise.
  rightHanded('aeronautics.generic.pull_when_clockwise'),

  /// Pushes when turning clockwise.
  leftHanded('aeronautics.generic.push_when_clockwise');

  const ThrustDirection(this.translationKey);

  /// The translation key of the option.
  final String translationKey;

  /// The scroll option value (`0` or `1`).
  int get optionIndex => this == rightHanded ? 0 : 1;

  static ThrustDirection fromIndex(int index) =>
      index == 1 ? ThrustDirection.leftHanded : ThrustDirection.rightHanded;
}

/// The bearing's sail scanning and thrust model.
final class PropellerBearingLogic {
  /// The number of sail blocks, as a power: thrust grows with its 1.5th power.
  double totalSailPower = 0;

  /// The local positions of the sails in the contraption.
  final List<Pos> sailPositions = [];

  /// The discs the sails form, one per plane along the facing axis.
  final List<PropellerLayer> layers = [];

  /// The current rotation speed, in degrees per tick.
  double rotationSpeed = 0;

  /// Which way the propeller pushes.
  ThrustDirection thrustDirectionOption = ThrustDirection.rightHanded;

  /// Whether the bearing is winding down before it disassembles.
  bool disassemblySlowdown = false;

  /// The easing curve of the disassembly slowdown.
  final BearingSlowdownController slowdownController = BearingSlowdownController();

  /// The facing of the bearing block.
  Direction facing = Direction.north;

  /// `getDirectionIndependentSpeed`: the rotation speed with the facing's axis
  /// direction and the thrust option applied.
  double get directionIndependentSpeed {
    final axisStep = facing.axisDirection == AxisDirection.positive ? 1.0 : -1.0;
    final option = thrustDirectionOption == ThrustDirection.leftHanded ? -1.0 : 1.0;
    return axisStep * clampedRotationRate * (10 / 3) * option;
  }

  /// `getThrust`.
  double thrust(double configThrust) =>
      math.pow(totalSailPower, 1.5).toDouble() * directionIndependentSpeed * configThrust;

  /// `getAirflow`.
  double airflow(double configAirflowMult) =>
      math.sqrt(totalSailPower) * directionIndependentSpeed * configAirflowMult;

  /// `isActive`: the propeller turns and carries a contraption.
  bool isActive({required bool hasContraption}) =>
      rotationSpeed.abs() > 0.01 && hasContraption;

  /// `calculateStressApplied`: the stress the sails put on the network.
  double stressApplied({required bool running, required double impact}) {
    if (!running || disassemblySlowdown) return 0;
    final sails = math.max(totalSailPower, 2);
    return sails * impact;
  }

  /// `updateRotationSpeed`: the bearing eases towards [inputSpeed], slower when
  /// it carries more sails.
  void updateRotationSpeed(double inputSpeed) {
    var nextSpeed = convertToAngular(inputSpeed);
    if (inputSpeed == 0) nextSpeed = 0;

    if (totalSailPower > 0) {
      final factor = 0.4 / math.sqrt(totalSailPower);
      rotationSpeed = AeroConfig.lerp(factor.clamp(0.0, 1.0), rotationSpeed, nextSpeed);
    } else {
      rotationSpeed = nextSpeed;
    }
  }

  /// `getClampedRotationRate`: during the slowdown the rate never exceeds the
  /// rate the slowdown started with, so the propeller cannot pulse.
  double get clampedRotationRate {
    if (!disassemblySlowdown) return rotationSpeed;

    final initial = slowdownController.initialVelocity;
    final max = math.max(initial, 0.0);
    final min = math.min(initial, 0.0);
    return math.min(math.max(rotationSpeed, min), max);
  }

  /// `findSails`: scans the contraption's blocks for sails and rebuilds the
  /// discs.
  ///
  /// [isSail] decides whether a block counts (the windmill-sail tag, with the
  /// copycat panel resolved to its material by the caller), and [blockStates]
  /// gives the state of every captured block.
  void findSails(Map<Pos, BState> blockStates, bool Function(BState state) isSail) {
    sailPositions.clear();
    layers.clear();
    totalSailPower = 0;

    final boundsByOffset = <int, (int, int)>{};

    for (final entry in blockStates.entries) {
      if (!isSail(entry.value)) continue;

      final pos = entry.key;
      sailPositions.add(pos);
      totalSailPower += 1;

      final offset = facing.stepX * pos.$1 + facing.stepY * pos.$2 + facing.stepZ * pos.$3;
      final flattened = (
        pos.$1 - facing.stepX * offset,
        pos.$2 - facing.stepY * offset,
        pos.$3 - facing.stepZ * offset,
      );
      final radius =
          flattened.$1 * flattened.$1 + flattened.$2 * flattened.$2 + flattened.$3 * flattened.$3;

      final existing = boundsByOffset[offset];
      if (existing == null) {
        boundsByOffset[offset] = (radius, radius);
      } else {
        boundsByOffset[offset] = (
          math.min(existing.$1, radius),
          math.max(existing.$2, radius),
        );
      }
    }

    final offsets = boundsByOffset.keys.toList()..sort();
    for (final offset in offsets) {
      final (innerSq, outerSq) = boundsByOffset[offset]!;
      final inner = math.max(math.sqrt(innerSq.toDouble()) - 0.5, 0.0);
      final outer = math.sqrt(outerSq.toDouble()) + 0.5;
      layers.add(PropellerLayer((offset + 1).toDouble(), inner, outer));
    }
  }

  /// `startDisassemblySlowdown`: begins winding down towards the next symmetry
  /// angle.
  ///
  /// [blocks] is the contraption's local position to block key map, which the
  /// controller uses to detect the contraption's symmetry.
  void startDisassemblySlowdown({
    required double currentAngle,
    required Map<Pos, String> blocks,
  }) {
    if (disassemblySlowdown) return;

    slowdownController.generateFromBlocks(
      maxTime: 1 + BearingSlowdownController.timerScale * math.sqrt(totalSailPower),
      initialAngle: currentAngle,
      initialVelocity: rotationSpeed,
      facingDirection: facing,
      blocks: blocks,
    );

    disassemblySlowdown = true;
  }

  /// `updateSlowdownSpeed`: one tick of the easing curve.
  ///
  /// Returns the angle the contraption is at, and sets [rotationSpeed].
  /// Returns `null` when the slowdown finished and the bearing must disassemble.
  double? tickSlowdown() {
    if (slowdownController.stepGoal()) return null;

    rotationSpeed = slowdownController.speed(0);
    return slowdownController.angle(0);
  }

  /// The thrust direction, as a vector in the bearing's local frame.
  Vector3d thrustDirectionVector([Vector3d? dest]) =>
      (dest ?? Vector3d()).set(facing.stepX.toDouble(), facing.stepY.toDouble(), facing.stepZ.toDouble());
}
