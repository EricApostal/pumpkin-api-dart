// `TrackTargetingBlockItem` (server part): the block item of the station, signal and observer.
// The item selects a position on a track in its data components and, when the block is placed,
// stores the target (`TargetTrack`, `TargetDirection`, `Bezier`) as the block entity data the
// `TrackTargetingBehaviour` reads.
//
// Java -> Dart: the client half of `useOn` (the player's look angle, the overlay outlines and
// `useOnCurve`) is not ported; the host exposes neither the look angle nor item use on a block
// with a placement context. What is ported is the server logic the client and the placement use:
// the overlap validation (`withGraphLocation`), the item components (`selectedPos`,
// `selectedDirection`, `selectedBezier`) and the block entity data a placement stores.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/direction.dart';
import '../../common/pos.dart' hide pos;
import '../graph/edge_point_type.dart';
import '../graph/track_graph_helper.dart';
import '../graph/track_graph_location.dart';
import '../signal/track_edge_point.dart';
import '../track/bezier_track_point_location.dart';
import '../track/i_track_block.dart';
import '../track/track_level.dart';
import '../util/ctag.dart';

/// The item of the station block.
const String trackStationItem = 'create:track_station';

/// The item of the signal block.
const String trackSignalItem = 'create:track_signal';

/// The item of the observer block.
const String trackObserverItem = 'create:track_observer';

/// `TrackTargetingBlockItem.OverlapResult`.
enum OverlapResult {
  valid(null),
  occupied('track_target.occupied'),
  junction('track_target.no_junctions'),
  noTrack('track_target.invalid');

  const OverlapResult(this.feedback);

  /// The lang key below `create.` shown to the player, `null` when the target is valid.
  final String? feedback;
}

/// `getType(stack)`: the edge point type of a targeting item, `null` for other items.
EdgePointType<TrackEdgePoint>? targetingTypeOf(String itemKey) =>
    switch (itemKey) {
      trackStationItem => EdgePointType.STATION,
      trackSignalItem => EdgePointType.SIGNAL,
      trackObserverItem => EdgePointType.OBSERVER,
      _ => null,
    };

/// `withGraphLocation(level, pos, front, targetBezier, type, callback)`: validates that the track
/// position is free for an edge point of [type].
void withGraphLocation(
  TrackLevel level,
  Pos pos,
  bool front,
  BezierTrackPointLocation? targetBezier,
  EdgePointType<TrackEdgePoint> type,
  void Function(OverlapResult result, TrackGraphLocation? location) callback,
) {
  final state = level.stateAt(pos);
  final track = TrackBlockRegistry.ofState(state);
  if (track == null) {
    callback(OverlapResult.noTrack, null);
    return;
  }

  final trackAxes = track.getTrackAxes(level, pos, state);
  if (targetBezier == null && trackAxes.length > 1) {
    callback(OverlapResult.junction, null);
    return;
  }

  final targetDirection = front
      ? AxisDirection.positive
      : AxisDirection.negative;
  final location = targetBezier != null
      ? TrackGraphHelper.getBezierGraphLocationAt(
          level,
          pos,
          targetDirection,
          targetBezier,
        )
      : TrackGraphHelper.getGraphLocationAt(
          level,
          pos,
          targetDirection,
          trackAxes[0],
        );
  if (location == null) {
    callback(OverlapResult.noTrack, null);
    return;
  }

  final edge = location.graph.getConnection(
    location.edge.map(location.graph.locateNode),
  );
  if (edge == null) return;

  final edgeData = edge.getEdgeData();
  final edgePosition = location.position;
  for (final edgePoint in edgeData.getPoints()) {
    final otherEdgePosition = edgePoint.getLocationOn(edge);
    final distance = (edgePosition - otherEdgePosition).abs();
    if (distance > 0.75) continue;
    if (edgePoint.canCoexistWith(type, front) && distance < 0.25) continue;
    callback(OverlapResult.occupied, location);
    return;
  }

  callback(OverlapResult.valid, location);
}

/// The item components of a targeting item (`AllDataComponents`).
abstract final class TrackTargetingComponents {
  static const String selectedPos = 'create:track_targeting_item_selected_pos';
  static const String selectedDirection =
      'create:track_targeting_item_selected_direction';
  static const String bezier = 'create:track_targeting_item_bezier';

  /// `stack.get(TRACK_TARGETING_ITEM_SELECTED_POS)`.
  static Pos? readSelectedPos(ItemStack stack) {
    final bytes = stack.customComponent(selectedPos);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, (r) => r.readBlockPos());
    } on Object {
      return null;
    }
  }

  static void writeSelectedPos(ItemStack stack, Pos pos) =>
      stack.setCustomComponent(
        selectedPos,
        PacketBuffer.encode((w) => w.writeBlockPos(pos)),
      );

  static void clearSelectedPos(ItemStack stack) =>
      stack.removeCustomComponent(selectedPos);

  /// `stack.get(TRACK_TARGETING_ITEM_SELECTED_DIRECTION)`.
  static bool? readSelectedDirection(ItemStack stack) {
    final bytes = stack.customComponent(selectedDirection);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, (r) => r.readBool());
    } on Object {
      return null;
    }
  }

  static void writeSelectedDirection(ItemStack stack, bool front) =>
      stack.setCustomComponent(
        selectedDirection,
        PacketBuffer.encode((w) => w.writeBool(front)),
      );

  static void clearSelectedDirection(ItemStack stack) =>
      stack.removeCustomComponent(selectedDirection);

  /// `stack.get(TRACK_TARGETING_ITEM_BEZIER)`.
  static BezierTrackPointLocation? readBezier(ItemStack stack) {
    final bytes = stack.customComponent(bezier);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, BezierTrackPointLocation.read);
    } on Object {
      return null;
    }
  }

  static void writeBezier(ItemStack stack, BezierTrackPointLocation location) =>
      stack.setCustomComponent(bezier, PacketBuffer.encode(location.write));

  static void clearBezier(ItemStack stack) =>
      stack.removeCustomComponent(bezier);

  /// `stack.remove(...)` of the three targeting components.
  static void clearAll(ItemStack stack) {
    clearSelectedPos(stack);
    clearSelectedDirection(stack);
    clearBezier(stack);
  }
}

/// The block entity data a targeting item stores for the placement (`BLOCK_ENTITY_DATA`), the
/// compound `TrackTargetingBehaviour` reads: `TargetDirection`, `TargetTrack` and `Bezier`.
CTag targetingBlockEntityData({
  required Pos placedPos,
  required Pos selectedPos,
  required bool front,
  BezierTrackPointLocation? selectedBezier,
}) {
  final data = CTag();
  data.putBoolean('TargetDirection', front);

  if (selectedBezier != null) {
    final bezierTag = CTag();
    bezierTag.putInt('Segment', selectedBezier.segment);
    final key = selectedBezier.curveTarget - placedPos;
    bezierTag.putBlockPos('Key', key);
    data.putCompound('Bezier', bezierTag);
  }

  data.putBlockPos('TargetTrack', selectedPos - placedPos);
  return data;
}

/// `TrackTargetingBlockItem.getType(stack)`: the type of the item in [itemKey].
EdgePointType<TrackEdgePoint>? typeOfTargetingItem(String itemKey) =>
    targetingTypeOf(itemKey);

/// `stack.has(...)` helpers for the placement path.
bool hasTargetSelection(ItemStack stack) =>
    TrackTargetingComponents.readSelectedPos(stack) != null;
