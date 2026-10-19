// `GantryShaftBlock` / `GantryShaftBlockEntity` as pure logic: the part a shaft takes next to
// another, the pole placement, the pinion movement speed, the assembly rule and the redstone
// rules. The block entity and the block behaviour live in `gantry_shaft.dart`.
import '../geometry.dart';
import '../placement_helpers.dart';
import '../settings.dart';

const String gantryShaftKey = 'create:gantry_shaft';

/// `GantryShaftBlock.updateShape`: the state of [state] when the neighbour in [direction] is
/// [neighbour]. The ends of a line turn into `middle`, a lone shaft into `start`/`end`.
KState gantryShaftUpdatePart(KState state, Dir direction, KState neighbour) {
  final facing = state.dirOf('facing') ?? Dir.north;
  if (direction.axis != facing.axis) return state;
  final connect =
      neighbour.block == gantryShaftKey && neighbour.dirOf('facing') == facing;
  var part = state['part'] ?? 'single';
  if (direction.isPositive == facing.isPositive) {
    if (connect) {
      if (part == 'end') part = 'middle';
      if (part == 'single') part = 'start';
    } else {
      if (part == 'middle') part = 'end';
      if (part == 'start') part = 'single';
    }
  } else {
    if (connect) {
      if (part == 'start') part = 'middle';
      if (part == 'single') part = 'end';
    } else {
      if (part == 'middle') part = 'start';
      if (part == 'end') part = 'single';
    }
  }
  return state.set('part', part);
}

/// `GantryShaftBlockEntity.getPinionMovementSpeed`: blocks per tick, clamped so a gantry never
/// moves more than half a block per tick.
double gantryShaftPinionSpeed(KState state, double speed) {
  if (state.block != gantryShaftKey) return 0;
  return convertToLinear(-speed).clamp(-.49, .49);
}

/// `GantryShaftBlockEntity.canAssembleOn`: a carriage can assemble on the shaft only when the
/// pinion would pull the gantry away from the shaft's middle.
bool gantryShaftCanAssemble(KState state, double speed) {
  if (state.block != gantryShaftKey) return false;
  if (state.flag('powered')) return false;
  final pinion = gantryShaftPinionSpeed(state, speed);
  return switch (state['part'] ?? 'single') {
    'end' => pinion < 0,
    'middle' => pinion != 0,
    'start' => pinion > 0,
    _ => false,
  };
}

/// `GantryShaftBlock.shouldBePowered`: a shaft is powered by a redstone signal or by a powered
/// shaft of the same facing on its axis.
bool gantryShaftShouldBePowered(
  KState state,
  KPos pos,
  bool neighborSignal,
  bool Function(KPos) isLoaded,
  KState Function(KPos) stateAt,
) {
  var shouldPower = neighborSignal;
  final facing = state.dirOf('facing') ?? Dir.north;
  for (final d in Dir.inAxis(facing.axis)) {
    final neighbourPos = pos.relative(d);
    if (!isLoaded(neighbourPos)) continue;
    final neighbourState = stateAt(neighbourPos);
    if (neighbourState.block != gantryShaftKey) continue;
    if (neighbourState.dirOf('facing') != facing) continue;
    shouldPower = shouldPower || neighbourState.flag('powered');
  }
  return shouldPower;
}

/// `GantryShaftBlock.PlacementHelper.getOffset` (a `PoleHelper` keyed on `facing`): the next
/// gantry shaft along the clicked shaft's axis. The placed shaft copies the clicked shaft's
/// facing and powered state.
PlacementOffset gantryShaftPoleOffset(
  HelperWorld w,
  KPos pos,
  KState state,
  (double, double, double) hit,
) {
  final facing = state.dirOf('facing') ?? Dir.north;
  final directions = orderedByDistance(pos, hit, (d) => d.axis == facing.axis);
  for (final dir in directions) {
    var count = 0;
    var check = pos.relative(dir);
    while (true) {
      final s = w.stateAt(check);
      if (s.block != gantryShaftKey ||
          (s.dirOf('facing') ?? Dir.north).axis != dir.axis)
        break;
      count++;
      check = check.relative(dir);
    }
    if (count >= w.placementAssistRange) continue;
    final newPos = pos.relative(dir, count + 1);
    if (w.canBeReplaced(newPos)) {
      return PlacementOffset.at(
        newPos,
        (s) => s.setAll({
          'facing': state['facing'] ?? 'north',
          'powered': state['powered'] ?? 'false',
        }),
      );
    }
  }
  return PlacementOffset.fail();
}
