// The structure of the large water wheel and its structural blocks (pure).
import 'geometry.dart';

/// `WaterWheelBlock.canSurvive`: wheels next to each other must share the axis
/// of the side they touch.
bool waterWheelCanSurvive(
  KState Function(KPos) stateAt,
  KPos pos,
  KState state,
) {
  if (!state.isCreate('water_wheel')) return false;
  final axis = (state.dirOf('facing') ?? Dir.north).axis;
  for (final direction in Dir.values) {
    final neighbour = stateAt(pos.relative(direction));
    if (!neighbour.isCreate('water_wheel')) continue;
    if ((neighbour.dirOf('facing') ?? Dir.north).axis != axis ||
        axis != direction.axis) {
      return false;
    }
  }
  return true;
}

/// `WaterWheelStructuralBlock.getMaster`: follows the structural blocks towards
/// the wheel.
KPos waterWheelMaster(KState Function(KPos) stateAt, KPos pos, KState state) {
  final direction = state.dirOf('facing') ?? Dir.north;
  final targetedPos = pos.relative(direction);
  final targetedState = stateAt(targetedPos);
  if (targetedState.isCreate('water_wheel_structure')) {
    return waterWheelMaster(stateAt, targetedPos, targetedState);
  }
  return targetedPos;
}

/// `WaterWheelStructuralBlock.stillValid`.
bool waterWheelStructureValid(
  KState Function(KPos) stateAt,
  KPos pos,
  KState state, {
  required bool directlyAdjacent,
}) {
  if (!state.isCreate('water_wheel_structure')) return false;

  final direction = state.dirOf('facing') ?? Dir.north;
  final targetedPos = pos.relative(direction);
  final targetedState = stateAt(targetedPos);

  if (!directlyAdjacent &&
      waterWheelStructureValid(
        stateAt,
        targetedPos,
        targetedState,
        directlyAdjacent: true,
      )) {
    return true;
  }
  return targetedState.isCreate('large_water_wheel') &&
      targetedState.axisOf('axis') != direction.axis;
}

/// The structural blocks a large water wheel at [pos] needs (`LargeWaterWheelBlock.tick`):
/// position -> required `facing` of the structure block.
List<(KPos, Dir)> largeWaterWheelStructure(KPos pos, KAxis axis) {
  final result = <(KPos, Dir)>[];
  for (final side in Dir.values) {
    if (side.axis == axis) continue;
    for (final secondary in [false, true]) {
      final targetSide = secondary ? side.clockWise(axis) : side;
      final structurePos = (secondary ? pos.relative(side) : pos).relative(
        targetSide,
      );
      result.add((structurePos, targetSide.opposite));
    }
  }
  return result;
}

/// The eight positions in the plane of a large wheel around [pos] that must be free.
List<KPos> largeWaterWheelFootprint(KPos pos, KAxis axis) {
  final result = <KPos>[];
  for (var x = -1; x <= 1; x++) {
    for (var y = -1; y <= 1; y++) {
      for (var z = -1; z <= 1; z++) {
        if (axis.choose(x, y, z) != 0) continue;
        if (x == 0 && y == 0 && z == 0) continue;
        result.add(pos.offset(x, y, z));
      }
    }
  }
  return result;
}
