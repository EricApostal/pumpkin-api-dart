// `TrackBlockItem` (server part): the item of a track block. Selecting a track stores the
// `create:track_connecting_from` component the placement (`TrackPlacement.tryConnect`) reads; the
// client half of Java (`useOn`, the sprint extender packet, `isFoil` rendering) is not ported
// because the host exposes neither the player's look angle nor item use on a block.
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import 'i_track_block.dart';
import 'track_level.dart';
import 'track_placement.dart' show ConnectingFrom;

abstract final class TrackBlockItem {
  /// `select(world, pos, lookVec, heldItem)`: stores the curve start of the nearest track axis in
  /// [stack]'s `connectingFrom`. Returns false for a block that is no track.
  static bool select(
    TrackLevel level,
    Pos pos,
    Vec3 lookVec,
    TrackItemStack stack,
  ) {
    final blockState = level.stateAt(pos);
    final track = TrackBlockRegistry.ofState(blockState);
    if (track == null) return false;

    final nearestTrackAxis = track.getNearestTrackAxis(
      level,
      pos,
      blockState,
      lookVec,
    );
    final axis =
        nearestTrackAxis.getFirst() *
        (nearestTrackAxis.getSecond() == AxisDirection.positive ? -1 : 1);
    final end = track.getCurveStart(level, pos, blockState, axis);
    final normal = track.getUpNormal(level, pos, blockState).normalized;

    stack.connectingFrom = ConnectingFrom(pos, axis, normal, end);
    return true;
  }

  /// `clearSelection(stack)`.
  static void clearSelection(TrackItemStack stack) =>
      stack.connectingFrom = null;

  /// `isFoil(stack)`.
  static bool isFoil(TrackItemStack stack) => stack.connectingFrom != null;
}
