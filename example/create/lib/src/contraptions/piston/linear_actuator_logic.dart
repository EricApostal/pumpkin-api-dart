// The pure math and state predicates of the linear actuators: `LinearActuatorBlockEntity` (the
// common part of the piston and the pulley), `MechanicalPistonBlockEntity` and the piston's
// extension poles. No host imports, so `dart test` runs the range and direction rules.
//
// Java: `content/contraptions/piston/{LinearActuatorBlockEntity,MechanicalPistonBlockEntity,
// MechanicalPistonBlock,PistonExtensionPoleBlock}` and `content/contraptions/pulley/
// PulleyBlockEntity`.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../kinetics/settings.dart' show convertToLinear;

// -- Piston blocks --------------------------------------------------------------------------

/// `MechanicalPistonBlock.isPiston`.
bool isPistonStateKey(String key) =>
    key == 'create:mechanical_piston' ||
    key == 'create:sticky_mechanical_piston';

/// `MechanicalPistonBlock.isExtensionPole`.
bool isPistonPole(BState state) => state.key == 'create:piston_extension_pole';

/// `MechanicalPistonBlock.isPistonHead`.
bool isPistonHead(BState state) => state.key == 'create:mechanical_piston_head';

/// `PistonExtensionPoleBlock.PlacementHelper.matchesAxis`.
bool pistonPoleMatchesAxis(BState state, Axis axis) =>
    isPistonPole(state) && (state.dir('facing')?.axis ?? Axis.y) == axis;

/// `MechanicalPistonBlock.tick`: the scheduled neighbour check clears a stale assembly exception
/// only when the piston still has an extension pole behind it, on the piston's own axis.
bool pistonHasPoleBehind(Direction facing, BState behind) =>
    pistonPoleMatchesAxis(behind, facing.axis);

/// `DirectionalAxisKineticBlock.getStateForPlacement` for a horizontal facing: the piston's
/// rotation axis (`axis_along_first`) turns to face a shaft above or below it. [shaftTowards]
/// answers `prefersConnectionTo(level, pos, side, true)`: the block next to the piston on [side]
/// has a shaft sticking out toward it.
bool pistonAlongFirstForPlacement(
  Direction facing,
  bool Function(Direction side) shaftTowards,
) {
  final faceAxis = facing.axis;
  if (!faceAxis.isHorizontal) return true;
  var alongFirst = faceAxis == Axis.z;
  if (shaftTowards(Direction.up) || shaftTowards(Direction.down)) {
    alongFirst = faceAxis == Axis.x;
  }
  return alongFirst;
}

// -- Movement math --------------------------------------------------------------------------

/// `convertToLinear(speed)` clamped to half a block per tick (`LinearActuatorBlockEntity`).
double actuatorMovementSpeed(double speed) => clampNum(convertToLinear(speed), -.49, .49);

/// `Mth.clamp((int) (offset + .5f), 0, extensionRange)`: the offset snapped to the block grid.
int actuatorGridOffset(double offset, int extensionRange) =>
    clampNum((offset + .5).truncate(), 0, extensionRange);

/// `getInterpolatedOffset`: the offset a client draws between two ticks.
double actuatorInterpolatedOffset(
  double offset,
  double partialTicks,
  double movementSpeed,
  int extensionRange,
) => clampNum(
  offset + (partialTicks - .5) * movementSpeed,
  0.0,
  extensionRange.toDouble(),
);

/// `tryDisassemble`: `MOVE_NEVER_PLACE` waits for the speed to change; `MOVE_PLACE_RETURNED`
/// waits until the contraption is back at the offset it was assembled at.
bool actuatorWaitsForSpeedChange({
  required bool neverPlace,
  required bool placeReturned,
  required double offset,
  required int initialOffset,
}) {
  if (neverPlace) return true;
  return placeReturned && (offset + .5).truncate() != initialOffset;
}

/// `MechanicalPistonBlockEntity.getMovementSpeed`: the offset change of this tick. The facing
/// axis and its direction decide the sign (`getAxisDirection().getStep()`; the z axis is
/// inverted), the movement stays between the retracted end and the extension range, and a
/// sequenced distance limit caps it.
double pistonMovementSpeed({
  required double speed,
  required Direction facing,
  required double offset,
  required int extensionRange,
  required double sequencedOffsetLimit,
}) {
  var movementSpeed = actuatorMovementSpeed(speed);
  movementSpeed = movementSpeed * -pistonDirectionModifier(facing);
  movementSpeed = clampNum(
    movementSpeed,
    0 - offset,
    extensionRange.toDouble() - offset,
  );
  if (sequencedOffsetLimit >= 0) {
    movementSpeed = clampNum(
      movementSpeed,
      -sequencedOffsetLimit,
      sequencedOffsetLimit,
    );
  }
  return movementSpeed;
}

/// `pistonDirection.getAxisDirection().getStep() * (axis == Axis.Z ? -1 : 1)`.
int pistonDirectionModifier(Direction facing) =>
    facing.axisDirection.step * (facing.axis == Axis.z ? -1 : 1);

// -- Pulley ---------------------------------------------------------------------------------

/// `PulleyBlockEntity.getExtensionRange`: the rope cannot be longer than the config allows or
/// than the distance to the bottom of the world.
int pulleyExtensionRange({
  required int y,
  required int minY,
  required int maxRopeLength,
}) => math.max(0, math.min(maxRopeLength, (y - 1) - minY));
