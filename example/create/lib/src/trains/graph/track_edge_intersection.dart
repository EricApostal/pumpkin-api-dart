// `TrackEdgeIntersection` (pure): a point where two edges cross.
import '../../common/data.dart';
import '../util/ctag.dart';
import '../util/uuid.dart';
import 'dimension_palette.dart';
import 'track_node_location.dart';

class TrackEdgeIntersection {
  double location = 0;
  late Couple<TrackNodeLocation> target;
  double targetLocation = 0;
  String? groupId;
  String id;

  TrackEdgeIntersection() : id = randomUuid();

  bool isNear(double location) => (location - this.location).abs() < 1 / 32.0;

  bool targets(TrackNodeLocation target1, TrackNodeLocation target2) =>
      target1 == target.getFirst() && target2 == target.getSecond() ||
      target1 == target.getSecond() && target2 == target.getFirst();

  CTag write(DimensionPalette? dimensions) {
    final nbt = CTag();
    nbt.putUuid('Id', id);
    if (groupId != null) nbt.putUuid('GroupId', groupId!);
    nbt.putDouble('Location', location);
    nbt.putDouble('TargetLocation', targetLocation);
    nbt.putCompoundList('TargetEdge', [target.first.write(dimensions), target.second.write(dimensions)]);
    return nbt;
  }

  static TrackEdgeIntersection read(CTag nbt, DimensionPalette? dimensions) {
    final intersection = TrackEdgeIntersection();
    intersection.id = nbt.getUuid('Id') ?? (throw const FormatException('TrackEdgeIntersection without Id'));
    if (nbt.contains('GroupId')) intersection.groupId = nbt.getUuid('GroupId');
    intersection.location = nbt.getDouble('Location');
    intersection.targetLocation = nbt.getDouble('TargetLocation');
    final list = nbt.getCompoundList('TargetEdge');
    intersection.target = Couple<TrackNodeLocation>(
      TrackNodeLocation.read(list.isNotEmpty ? list[0] : CTag(), dimensions),
      TrackNodeLocation.read(list.length > 1 ? list[1] : CTag(), dimensions),
    );
    return intersection;
  }
}
