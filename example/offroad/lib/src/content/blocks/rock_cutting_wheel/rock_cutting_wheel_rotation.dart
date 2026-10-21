// `RockCuttingWheelActor`'s rotation maths: which way a wheel on a borehead
// contraption visually turns, given where it sits on the contraption.
//
// The actor itself (`rock_cutting_wheel_actor.dart`) needs the live block entity
// and therefore the host; this decision is pure, so it is tested on the VM.
//
// Pure: no host imports.
//
// Java: `content/blocks/rock_cutting_wheel/RockCuttingWheelActor.java:78-134`
// ignore_for_file: implementation_imports
import 'package:create/src/common/common.dart' show Pos;
import 'package:create/src/common/direction.dart' show Axis, Direction;

/// `RockCuttingWheelActor`'s pure rotation decision.
abstract final class RockCuttingWheelRotation {
  /// `SEARCH_ORIGIN_OFFSET` (`RockCuttingWheelActor.java:76`).
  static const double searchOriginOffset = 1;

  /// `reverseRotation(bearingAxis, bearingSpeed, localDir, axisAlongFirst, localPos)`
  /// (`RockCuttingWheelActor.java:78`): whether the client animation turns the
  /// other way.
  static bool reverseRotation({
    required Axis bearingAxis,
    required double bearingSpeed,
    required Direction localDir,
    required bool axisAlongFirst,
    required Pos localPos,
  }) {
    final Axis rotationAxis;
    if (localDir.axis.isVertical) {
      rotationAxis = axisAlongFirst ? Axis.z : Axis.x;
    } else {
      final facingUp = axisAlongFirst == (localDir.stepX == 0);
      rotationAxis = facingUp ? Axis.y : localDir.clockWise.axis;
    }

    if (localDir.axis == bearingAxis) {
      switch (rotationAxis) {
        case Axis.z:
          if (localPos.$3 == 0) {
            // Roll towards the centre.
            if (localDir.axis == Axis.x) {
              return (localPos.$2 > 0) == (bearingSpeed > 0);
            }
            return (localPos.$1 > 0) != (bearingSpeed > 0);
          }
          // Roll along the rotation.
          return !(localPos.$3 > 0);
        case Axis.y:
          if (localPos.$2 == 0) {
            // Roll towards the centre.
            if (localDir.axis == Axis.z) {
              return ((localDir.stepZ > 0) == (localPos.$1 > 0)) != (bearingSpeed > 0);
            }
            return ((localDir.stepX > 0) == (localPos.$3 > 0)) == (bearingSpeed > 0);
          }
          // Roll along the rotation.
          return (localPos.$2 > 0) != (localDir.stepX < 0 || localDir.stepZ < 0);
        case Axis.x:
          if (localPos.$1 == 0) {
            // Roll towards the centre.
            if (localDir.axis == Axis.y) {
              return ((localDir.stepY > 0) == (localPos.$3 > 0)) != (bearingSpeed > 0);
            }
            return (localPos.$2 > 0) == (bearingSpeed > 0);
          }
          // Roll along the rotation.
          return (localPos.$1 > 0) != (localDir == Direction.down);
      }
    }

    if (bearingAxis == rotationAxis) return false;

    // TODO(parity): `RockCuttingWheelActor.java:132` — "the war never ends
    // (rotation direction for outwards pointing wheels)". The Java returns
    // false here too; the port keeps the same answer.
    return false;
  }

  /// Where the actor looks for the block it cuts
  /// (`RockCuttingWheelActor.java:165-167`): the centre of its block, one block
  /// along its facing.
  static (double, double, double) searchOrigin(Pos localPos, Direction facing) => (
    localPos.$1 + 0.5 + facing.stepX * searchOriginOffset,
    localPos.$2 + 0.5 + facing.stepY * searchOriginOffset,
    localPos.$3 + 0.5 + facing.stepZ * searchOriginOffset,
  );
}