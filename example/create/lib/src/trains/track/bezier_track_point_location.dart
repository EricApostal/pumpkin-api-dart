// `BezierTrackPointLocation` (pure): a segment of a curve, the value of the data component
// `create:track_targeting_item_bezier`.
import '../../common/common.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// `BezierTrackPointLocation(BlockPos curveTarget, int segment)`.
final class BezierTrackPointLocation {
  final Pos curveTarget;
  final int segment;

  const BezierTrackPointLocation(this.curveTarget, this.segment);

  /// `curveTarget()`.
  Pos getCurveTarget() => curveTarget;

  /// `segment()`.
  int getSegment() => segment;

  /// `STREAM_CODEC`: a packed block position and an int.
  void write(PacketWriter buffer) {
    buffer.writeBlockPos(curveTarget);
    buffer.writeInt(segment);
  }

  static BezierTrackPointLocation read(PacketReader buffer) {
    final pos = buffer.readBlockPos();
    return BezierTrackPointLocation(pos, buffer.readInt());
  }

  @override
  bool operator ==(Object other) =>
      other is BezierTrackPointLocation && other.curveTarget == curveTarget && other.segment == segment;

  @override
  int get hashCode => Object.hash(curveTarget, segment);

  @override
  String toString() => 'BezierTrackPointLocation($curveTarget, $segment)';
}
