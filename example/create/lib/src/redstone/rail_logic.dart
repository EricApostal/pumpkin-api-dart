// `ControllerRailBlock` as pure logic: the acceleration direction of a rail, how the power
// is interpolated between the two nearest powered rails, and the cart push.
import '../api/block_state.dart';
import '../common/common.dart';

const String controllerRailKey = 'create:controller_rail';

/// `getPointingTowards(state)`.
Direction railPointingTowards(String shape) => switch (shape) {
  'ascending_west' || 'east_west' => Direction.west,
  'ascending_east' => Direction.east,
  'ascending_south' => Direction.south,
  _ => Direction.north,
};

/// `isSlope()`.
bool railIsSlope(String shape) => shape.startsWith('ascending_');

/// `isReversedSlope(state)`.
bool railIsReversedSlope(String shape) => shape == 'ascending_south' || shape == 'ascending_east';

/// `isStateBackwards(state)`: `BACKWARDS ^ isReversedSlope`.
bool railIsBackwards(Map<String, String> props) =>
    (props['backwards'] == 'true') != railIsReversedSlope(props['shape'] ?? 'north_south');

/// `getAccelerationVector(state)` as a direction.
Direction railAcceleration(Map<String, String> props) {
  final pointing = railPointingTowards(props['shape'] ?? 'north_south');
  return railIsBackwards(props) ? pointing.opposite : pointing;
}

/// What the rail power calculation reads.
abstract interface class RailEnv {
  BState stateAt(Pos pos);

  /// `level.getBestNeighborSignal(pos)`.
  Future<int> bestNeighborSignal(Pos pos);
}

/// `findNextRail(from, world, reversed)`: the next controller rail along the acceleration
/// direction (or against it), on the same level or one block below / above.
Pos? findNextRail(Pos from, RailEnv env, {required bool reversed}) {
  final current = env.stateAt(from);
  if (current.key != controllerRailKey) return null;
  final accel = railAcceleration(current.props);
  final base = reversed ? from.relative(accel.opposite) : from.relative(accel);
  for (final test in [base, base.below, base.above]) {
    if (test.y > from.y && !railIsSlope(current['shape'] ?? '')) continue;
    final testState = env.stateAt(test);
    if (testState.key == controllerRailKey && railAcceleration(testState.props) == accel) return test;
  }
  return null;
}

/// `calculatePower(world, pos)`.
Future<int> calculateRailPower(Pos pos, RailEnv env) async {
  var newPower = await env.bestNeighborSignal(pos);
  if (newPower != 0) return newPower;

  var forwardDistance = 0;
  var backwardsDistance = 0;
  var lastForwardRail = pos;
  var lastBackwardsRail = pos;
  var forwardPower = 0;
  var backwardsPower = 0;

  for (var i = 0; i < 15; i++) {
    final testPos = findNextRail(lastForwardRail, env, reversed: false);
    if (testPos == null) break;
    forwardDistance++;
    lastForwardRail = testPos;
    forwardPower = await env.bestNeighborSignal(testPos);
    if (forwardPower != 0) break;
  }
  for (var i = 0; i < 15; i++) {
    final testPos = findNextRail(lastBackwardsRail, env, reversed: true);
    if (testPos == null) break;
    backwardsDistance++;
    lastBackwardsRail = testPos;
    backwardsPower = await env.bestNeighborSignal(testPos);
    if (backwardsPower != 0) break;
  }

  if (forwardDistance > 8 && backwardsDistance > 8) return 0;
  if (backwardsPower == 0 && forwardDistance <= 8) return forwardPower;
  if (forwardPower == 0 && backwardsDistance <= 8) return backwardsPower;
  if (backwardsPower != 0 && forwardPower != 0) {
    return ((backwardsPower * forwardDistance + forwardPower * backwardsDistance) / (forwardDistance + backwardsDistance))
        .ceil();
  }
  return 0;
}

/// The velocity `entityInside` gives a minecart, or `null` for no change.
/// [motion] is the cart's current movement per tick, [maxSpeed] its `getMaxSpeedWithRail()`.
({Vec3 velocity, bool decelerate})? cartVelocity({
  required Map<String, String> props,
  required Vec3 motion,
  required Vec3 cartPos,
  required Pos railPos,
  double maxSpeed = 0.4,
}) {
  final accel = railAcceleration(props);
  final accelVec = accel.unitVec3;
  final power = int.tryParse(props['power'] ?? '') ?? 0;
  final targetSpeed = maxSpeed * power / 15.0;

  final dot = motion.$1 * accelVec.$1 + motion.$2 * accelVec.$2 + motion.$3 * accelVec.$3;
  final lengthSqr = motion.$1 * motion.$1 + motion.$2 * motion.$2 + motion.$3 * motion.$3;
  if ((dot >= 0 || lengthSqr < 0.0001) && targetSpeed > 0) {
    return (velocity: (accelVec.$1 * targetSpeed, accelVec.$2 * targetSpeed, accelVec.$3 * targetSpeed), decelerate: false);
  }
  // decelerateCart: drift to the centre of the rail.
  final center = railPos.center;
  return (velocity: ((center.$1 - cartPos.$1) / 16, 0.0, (center.$3 - cartPos.$3) / 16), decelerate: true);
}

/// `isStableWith(testState, world, pos)`: support below, and for slopes also on the high side.
bool railIsStable(String shape, bool Function(Pos) canSupportRigid, Pos pos) =>
    canSupportRigid(pos.below) && (!railIsSlope(shape) || canSupportRigid(pos.relative(railPointingTowards(shape))));

/// `RailShape.rotate` by a quarter turns count (clockwise), as `Blocks.POWERED_RAIL.rotate`.
String railRotateShape(String shape, BlockRotation rotation) {
  switch (rotation) {
    case BlockRotation.none:
      return shape;
    case BlockRotation.clockwise180:
      return switch (shape) {
        'north_south' => 'north_south',
        'east_west' => 'east_west',
        'ascending_east' => 'ascending_west',
        'ascending_west' => 'ascending_east',
        'ascending_north' => 'ascending_south',
        'ascending_south' => 'ascending_north',
        _ => shape,
      };
    case BlockRotation.counterclockwise90:
      return switch (shape) {
        'north_south' => 'east_west',
        'east_west' => 'north_south',
        'ascending_east' => 'ascending_north',
        'ascending_west' => 'ascending_south',
        'ascending_north' => 'ascending_west',
        'ascending_south' => 'ascending_east',
        _ => shape,
      };
    case BlockRotation.clockwise90:
      return switch (shape) {
        'north_south' => 'east_west',
        'east_west' => 'north_south',
        'ascending_east' => 'ascending_south',
        'ascending_west' => 'ascending_north',
        'ascending_north' => 'ascending_east',
        'ascending_south' => 'ascending_west',
        _ => shape,
      };
  }
}

/// `ControllerRailBlock.rotate(state, rotation)`: the new `(shape, backwards)`.
({String shape, bool backwards}) railRotate(Map<String, String> props, BlockRotation rotation) {
  if (rotation == BlockRotation.none) {
    return (shape: props['shape'] ?? 'north_south', backwards: props['backwards'] == 'true');
  }
  final shape = railRotateShape(props['shape'] ?? 'north_south', rotation);
  var backwards = props['backwards'] == 'true';
  if (rotation == BlockRotation.clockwise180 ||
      (railPointingTowards(shape).axis == Axis.z) == (rotation == BlockRotation.counterclockwise90)) {
    backwards = !backwards;
  }
  return (shape: shape, backwards: backwards);
}
