// `TrackBlockEntityTilt` (pure): the smoothing of slopes that meet at a level track. When a track
// block has exactly two sloped curves leaving it in opposite directions, the block itself tilts
// (`Smoothing` angle) and the curves are re-targeted to the raised handle.
import 'dart:math' as math;

import '../../common/common.dart';
import '../graph/track_node_location.dart';
import 'bezier_connection.dart';
import 'i_track_block.dart';
import 'track_block_entity.dart';
import 'track_propagator.dart';
import 'track_block.dart' show isTrackBlockState;
import 'track_shape.dart' show vdistSqr, vmul, vnorm;

class TrackBlockEntityTilt {
  /// `smoothingAngle` (`Optional<Double>`): `null` when the block is not tilted.
  double? smoothingAngle;
  Couple<Pair<Vec3, int>?>? _previousSmoothingHandles;

  final TrackBlockEntity blockEntity;

  TrackBlockEntityTilt(this.blockEntity);

  /// `smoothingAngle.isPresent()`.
  bool get hasSmoothing => smoothingAngle != null;

  /// `tryApplySmoothing()`.
  Future<void> tryApplySmoothing() async {
    if (smoothingAngle != null) return;

    final discoveredSlopes = Couple<BezierConnection?>(null, null);
    Vec3? axis;

    final level = blockEntity.getLevel();
    if (level == null) return;
    final worldPosition = blockEntity.getBlockPos();
    final blockState = level.stateAt(worldPosition);

    final itb = TrackBlockRegistry.ofState(blockState);
    if (itb == null) return;
    final axes = itb.getTrackAxes(level, worldPosition, blockState);
    if (axes.length != 1) return;
    if (axes[0].y != 0) return;
    if (blockEntity.boundLocation != null) return;

    for (final bezierConnection in blockEntity.connections.values) {
      if (bezierConnection.starts.getFirst().y == bezierConnection.starts.getSecond().y) continue;
      final normedAxis = vnorm(bezierConnection.axes.getFirst());

      if (axis != null) {
        if (discoveredSlopes.getSecond() != null) return;
        if (normedAxis.dot(axis) > -1 + 1 / 64.0) return;
        discoveredSlopes.setSecond(bezierConnection);
        continue;
      }

      axis = normedAxis;
      discoveredSlopes.setFirst(bezierConnection);
    }

    if (discoveredSlopes.either((c) => c == null)) return;
    var slopes = Couple<BezierConnection>(discoveredSlopes.getFirst()!, discoveredSlopes.getSecond()!);
    if (slopes.getFirst().starts.getSecond().y > slopes.getSecond().starts.getSecond().y) slopes = slopes.swap();

    final lowStarts = slopes.getFirst().starts;
    final highStarts = slopes.getSecond().starts;
    final lowestPoint = lowStarts.getSecond();
    final highestPoint = highStarts.getSecond();

    if (lowestPoint.y > lowStarts.getFirst().y) return;
    if (highestPoint.y < highStarts.getFirst().y) return;

    await blockEntity.removeInboundConnections(false);
    blockEntity.connections.clear();
    TrackPropagator.onRailRemoved(level, worldPosition, blockState);

    final hDistance = slopes.getFirst().getLength() + slopes.getSecond().getLength();
    final baseAxis = slopes.getFirst().axes.getFirst();
    final baseAxisLength = baseAxis.x != 0 && baseAxis.z != 0 ? math.sqrt(2) : 1.0;
    final vDistance = highestPoint.y - lowestPoint.y;
    final m = vDistance / hDistance;

    final diff = highStarts.getFirst() - lowStarts.getFirst();
    final flipRotation = diff.dot(vnorm((1.0, 0.0, 2.0))) <= 0;
    smoothingAngle = (math.atan2(m, 1) * 180 / math.pi) * (flipRotation ? -1 : 1);

    final smoothingParam = (m * baseAxisLength * 16).toInt().clamp(0, 15);

    final smoothingResult = Couple<int>(0, smoothingParam);
    final raisedOffset =
        vnorm(vnorm(diff) + (0.0, m.clamp(0.0, 1 - 1 / 512.0).toDouble(), 0.0)) * baseAxisLength;

    highStarts.setFirst(lowStarts.getFirst() + raisedOffset);

    var first = true;
    for (final bezierConnection in slopes.values) {
      final smoothingToApply = smoothingResult.get(first);

      bezierConnection.smoothing ??= Couple<int>(0, 0);
      bezierConnection.smoothing!.setFirst(smoothingToApply);
      bezierConnection.axes.setFirst(
        vnorm(bezierConnection.axes.getFirst() + (0.0, (first ? 1 : -1) * -m, 0.0)),
      );

      first = false;
      final otherPosition = bezierConnection.getKey();
      final otherState = level.stateAt(otherPosition);
      if (!isTrackBlockState(otherState)) continue;
      await level.setBlockAndUpdate(otherPosition, withHasBe(otherState, true));
      final otherBE = level.getTrackBlockEntity(otherPosition);
      if (otherBE != null) {
        await blockEntity.addConnection(bezierConnection);
        await otherBE.addConnection(bezierConnection.secondary());
      }
    }
  }

  /// `captureSmoothingHandles()`.
  void captureSmoothingHandles() {
    var first = true;
    final handles = Couple<Pair<Vec3, int>?>(null, null);
    _previousSmoothingHandles = handles;
    for (final bezierConnection in blockEntity.connections.values) {
      handles.set(
        first,
        Pair<Vec3, int>(bezierConnection.starts.getFirst(), bezierConnection.smoothing == null ? 0 : bezierConnection.smoothing!.getFirst()),
      );
      first = false;
    }
  }

  /// `undoSmoothing()`.
  Future<void> undoSmoothing() async {
    if (smoothingAngle == null) return;
    if (_previousSmoothingHandles == null) return;
    if (blockEntity.connections.length == 2) return;

    final level = blockEntity.getLevel();
    if (level == null) return;
    final worldPosition = blockEntity.getBlockPos();
    final blockState = level.stateAt(worldPosition);

    final validConnections = <BezierConnection>[];
    for (final bezierConnection in blockEntity.connections.values) {
      final otherPosition = bezierConnection.getKey();
      final otherBE = level.getTrackBlockEntity(otherPosition);
      if (otherBE != null && otherBE.connections.containsKey(worldPosition)) validConnections.add(bezierConnection);
    }

    await blockEntity.removeInboundConnections(false);
    TrackPropagator.onRailRemoved(level, worldPosition, blockState);
    blockEntity.connections.clear();
    smoothingAngle = null;

    for (final bezierConnection in validConnections) {
      await blockEntity.addConnection(restoreToOriginalCurve(bezierConnection));

      final otherPosition = bezierConnection.getKey();
      final otherState = level.stateAt(otherPosition);
      if (!isTrackBlockState(otherState)) continue;
      await level.setBlockAndUpdate(otherPosition, withHasBe(otherState, true));
      final otherBE = level.getTrackBlockEntity(otherPosition);
      if (otherBE != null) await otherBE.addConnection(bezierConnection.secondary());
    }

    blockEntity.notifyUpdate();
    _previousSmoothingHandles = null;
    TrackPropagator.onRailAdded(level, worldPosition, blockState);
  }

  /// `restoreToOriginalCurve(bc)`.
  BezierConnection restoreToOriginalCurve(BezierConnection bezierConnection) {
    final s = bezierConnection.smoothing;
    if (s != null) {
      s.setFirst(0);
      if (s.getFirst() == 0 && s.getSecond() == 0) bezierConnection.smoothing = null;
    }
    final raisedStart = bezierConnection.starts.getFirst();
    bezierConnection.starts.setFirst(TrackNodeLocation.fromVec(raisedStart).getLocation());
    bezierConnection.axes.setFirst(vnorm(vmul(bezierConnection.axes.getFirst(), 1, 0, 1)));
    return bezierConnection;
  }

  /// `getYOffsetForAxisEnd(end)`.
  int getYOffsetForAxisEnd(Vec3 end) {
    if (smoothingAngle == null) return 0;
    for (final bezierConnection in blockEntity.connections.values) {
      if (compareHandles(bezierConnection.starts.getFirst(), end)) return bezierConnection.yOffsetAt(end);
    }
    final handles = _previousSmoothingHandles;
    if (handles == null) return 0;
    for (final handle in handles.values) {
      if (handle != null && compareHandles(handle.getFirst(), end)) return handle.getSecond();
    }
    return 0;
  }

  /// `compareHandles(handle1, handle2)`.
  static bool compareHandles(Vec3 handle1, Vec3 handle2) =>
      vdistSqr(
        vmul(TrackNodeLocation.fromVec(handle1).getLocation(), 1, 0, 1),
        vmul(TrackNodeLocation.fromVec(handle2).getLocation(), 1, 0, 1),
      ) <
      toFloat(1 / 512);
}
