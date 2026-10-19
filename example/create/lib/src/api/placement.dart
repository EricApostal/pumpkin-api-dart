// Catnip's placement assist (`IPlacementHelper`, `PlacementOffset`, `PoleHelper`) as pure
// logic: where the next block of a pole or row goes when a player right-clicks the last one
// with the same item. The caller (a block's use-with-item hook) places the result with the host.
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'block_state.dart';

/// `PlacementOffset`: the position of the block to place and how to adjust its default state.
final class PlacementOffset {
  final bool success;
  final Pos pos;
  final BState Function(BState state) transform;

  const PlacementOffset._(this.success, this.pos, this.transform);

  static BState _identity(BState s) => s;

  /// `PlacementOffset.fail()`.
  static const PlacementOffset fail = PlacementOffset._(false, (0, 0, 0), _identity);

  /// `PlacementOffset.success(pos, transform)`.
  factory PlacementOffset.at(Pos pos, [BState Function(BState state)? transform]) =>
      PlacementOffset._(true, pos, transform ?? _identity);

  bool get isSuccessful => success;
}

/// `IPlacementHelper.orderedByDistance(pos, hit, directions)`: the directions sorted by the distance of
/// their unit vector to the hit point relative to the block centre (the closest face first).
List<Direction> orderedByDistance(Pos pos, (double, double, double) hit, [Iterable<Direction>? directions]) {
  final c = pos.center;
  final centerToHit = (hit.$1 - c.$1, hit.$2 - c.$2, hit.$3 - c.$3);
  final dirs = (directions ?? Iterate.directions).toList();
  double dist(Direction d) {
    final dx = d.stepX - centerToHit.$1, dy = d.stepY - centerToHit.$2, dz = d.stepZ - centerToHit.$3;
    return dx * dx + dy * dy + dz * dz;
  }

  // Dart's sort is not stable for small lists the way Java's is; keep the original order on ties.
  final indexed = [for (var i = 0; i < dirs.length; i++) (dirs[i], dist(dirs[i]), i)];
  indexed.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : a.$3.compareTo(b.$3);
  });
  return [for (final e in indexed) e.$1];
}

/// `orderedByDistance(pos, hit, filter)`.
List<Direction> orderedByDistanceWhere(Pos pos, (double, double, double) hit, bool Function(Direction) include) =>
    orderedByDistance(pos, hit, Iterate.directions.where(include));

/// `orderedByDistanceExceptAxis`.
List<Direction> orderedByDistanceExceptAxis(Pos pos, (double, double, double) hit, Axis axis,
        [bool Function(Direction)? include]) =>
    orderedByDistanceWhere(pos, hit, (d) => d.axis != axis && (include?.call(d) ?? true));

/// `orderedByDistanceOnlyAxis`.
List<Direction> orderedByDistanceOnlyAxis(Pos pos, (double, double, double) hit, Axis axis,
        [bool Function(Direction)? include]) =>
    orderedByDistanceWhere(pos, hit, (d) => d.axis == axis && (include?.call(d) ?? true));

/// `PoleHelper.getOffset`: extends a pole of blocks that match [matches] along its axis.
///
/// [state] and [pos] are the clicked block, [hit] the exact click location, [range] the
/// `placementAssistRange` (plus 4 with the extendo grip). [transformProperty] names the property
/// copied from the clicked state to the new block (`PoleHelper.property`).
PlacementOffset poleOffset({
  required BlockGetter level,
  required BState state,
  required Pos pos,
  required (double, double, double) hit,
  required bool Function(BState state) matches,
  required Axis Function(BState state) axisOf,
  required String transformProperty,
  required int range,
}) {
  final axis = axisOf(state);
  final directions = orderedByDistanceWhere(pos, hit, (d) => d.axis == axis);
  for (final dir in directions) {
    var poles = 0;
    var check = pos.relative(dir);
    while (matches(level.stateAt(check)) && axisOf(level.stateAt(check)) == dir.axis) {
      poles++;
      check = check.relative(dir);
    }
    if (poles >= range) continue;
    final newPos = pos.relative(dir, poles + 1);
    if (level.canBeReplaced(newPos)) {
      final value = state[transformProperty];
      return PlacementOffset.at(newPos, (b) => value == null ? b : b.setValue(transformProperty, value));
    }
  }
  return PlacementOffset.fail;
}
