// The pure part of the train assembly of a station (`StationBlockEntity`): scanning the assembly
// track for bogeys, the validity of a bogey offset, the assembly direction and the creation of the
// wheel points on the graph. Works on [BlockGetter] / [ITrackBlock] and the graph classes, so it runs
// on the Dart VM. The block entity (`station_block_entity.dart`) glues it to the world.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../bogey/abstract_bogey_block.dart';
import '../entity/travelling_point.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../manager/create.dart';
import '../track/i_track_block.dart';

/// The lang key (below `create.`) and arguments of an assembly failure shown on the station.
final class StationAssemblyError {
  /// `train_assembly.no_bogeys`.
  final String langKey;
  final List<Object> args;

  const StationAssemblyError(this.langKey, [this.args = const []]);

  @override
  String toString() => 'StationAssemblyError($langKey, $args)';
}

/// The wheel points created for the bogeys of a train, or why that failed. A failure without an
/// [error] is silent (Java only logs a warning).
final class AssemblyPoints {
  final TrackGraph? graph;
  final List<TravellingPoint> points;
  final StationAssemblyError? error;
  final String? warning;

  const AssemblyPoints._(this.graph, this.points, this.error, this.warning);

  factory AssemblyPoints.ok(TrackGraph graph, List<TravellingPoint> points) =>
      AssemblyPoints._(graph, points, null, null);

  factory AssemblyPoints.error(StationAssemblyError error) => AssemblyPoints._(null, const [], error, null);

  factory AssemblyPoints.warn(String warning) => AssemblyPoints._(null, const [], null, warning);

  factory AssemblyPoints.silent() => const AssemblyPoints._(null, [], null, null);

  bool get isOk => graph != null && error == null && warning == null;
}

/// The assembly state of a station: where the bogeys are along the assembly track.
class StationAssembly {
  Direction? assemblyDirection;
  int assemblyLength = 0;
  List<int>? bogeyLocations;
  List<AbstractBogeyBlock?>? bogeyTypes;
  List<bool>? upsideDownBogeys;
  int bogeyCount = 0;

  /// `getAssemblyDirection()`: the direction of the track from the station marker (cached).
  Direction getAssemblyDirection(
    BlockGetter level,
    ITrackBlock track,
    Pos targetPosition,
    BState trackState,
    AxisDirection targetDirection,
  ) {
    final cached = assemblyDirection;
    if (cached != null) return cached;
    final axis = vnormalize(track.getTrackAxes(level, targetPosition, trackState)[0]) * targetDirection.step;
    return assemblyDirection = Direction.nearest(axis.$1, axis.$2, axis.$3);
  }

  /// `refreshAssemblyInfo()` without the world bookkeeping: scans the track in the assembly
  /// direction for bogeys. Returns `true` when `assemblyLength` changed.
  bool refresh(
    BlockGetter level,
    ITrackBlock track,
    Pos targetPosition,
    BState trackState,
    AxisDirection targetDirection, {
    required int maxLength,
    required int maxBogeyCount,
  }) {
    final prevLength = assemblyLength;
    final direction = getAssemblyDirection(level, track, targetPosition, trackState, targetDirection);

    var currentPos = targetPosition.relative(direction);

    final up = track.getUpNormal(level, targetPosition, trackState);
    final bogeyOffset = posContaining(up);

    var bogeyIndex = 0;
    final locations = bogeyLocations ??= List<int>.filled(maxBogeyCount, -1);
    final types = bogeyTypes ??= List<AbstractBogeyBlock?>.filled(maxBogeyCount, null);
    final upsideDowns = upsideDownBogeys ??= List<bool>.filled(maxBogeyCount, false);
    locations.fillRange(0, locations.length, -1);
    types.fillRange(0, types.length, null);
    upsideDowns.fillRange(0, upsideDowns.length, false);

    for (var i = 0; i < maxLength; i++) {
      if (i == maxLength - 1) {
        assemblyLength = i;
        break;
      }
      if (!track.trackEquals(trackState, level.stateAt(currentPos))) {
        assemblyLength = i - 1 < 0 ? 0 : i - 1;
        break;
      }

      var potentialBogeyState = level.stateAt(bogeyOffset + currentPos);
      final upsideDownBogeyOffset = (bogeyOffset.x, bogeyOffset.y * -1, bogeyOffset.z);
      if (bogeyIndex < locations.length) {
        final bogey = AbstractBogeyBlock.byKey(potentialBogeyState.key);
        if (bogey != null && !bogey.isUpsideDown(potentialBogeyState)) {
          types[bogeyIndex] = bogey;
          locations[bogeyIndex] = i;
          upsideDowns[bogeyIndex] = false;
          bogeyIndex++;
        } else {
          potentialBogeyState = level.stateAt(upsideDownBogeyOffset + currentPos);
          final upsideDownBogey = AbstractBogeyBlock.byKey(potentialBogeyState.key);
          if (upsideDownBogey != null && upsideDownBogey.isUpsideDown(potentialBogeyState)) {
            types[bogeyIndex] = upsideDownBogey;
            locations[bogeyIndex] = i;
            upsideDowns[bogeyIndex] = true;
            bogeyIndex++;
          }
        }
      }

      currentPos = currentPos.relative(direction);
    }

    bogeyCount = bogeyIndex;
    return prevLength != assemblyLength;
  }

  /// `isValidBogeyOffset(i)`.
  bool isValidBogeyOffset(int i) {
    if ((i < 3 || bogeyCount == 0) && i != 0) return false;
    final locations = bogeyLocations;
    if (locations == null) return true;
    for (final j in locations) {
      if (j == -1) break;
      if (i >= j - 2 && i <= j + 2) return false;
    }
    return true;
  }

  /// `tryEnterAssemblyMode()`: the track under the station must run along exactly one axis.
  static bool canEnterAssemblyMode(ITrackBlock track, BlockGetter level, Pos targetPosition, BState trackState) {
    final trackAxis = track.getTrackAxes(level, targetPosition, trackState)[0];

    var axisFound = false;
    for (final axis in Iterate.axes) {
      if (VecHelper.getCoordinate(trackAxis, axis) == 0) continue;
      if (axisFound) return false;
      axisFound = true;
    }

    return true;
  }

  /// The bounding box `assemblyAreas` remembers for the track: from the first track block after the
  /// station to the end of the assembly length.
  BlockBounds assemblyArea(Pos targetPosition) {
    final direction = assemblyDirection!;
    final startPosition = targetPosition.relative(direction);
    final trackEnd = startPosition.relative(direction, assemblyLength - 1);
    return BlockBounds.fromCorners(startPosition, trackEnd);
  }

  /// The first half of `assemble(playerUUID)`: the wheel offsets of the bogeys and the
  /// [TravellingPoint]s on the graph.
  AssemblyPoints createTravellingPoints(
    BlockGetter level,
    ITrackBlock track,
    Pos trackPosition,
    BState trackState,
  ) {
    final locations = bogeyLocations;
    final types = bogeyTypes;
    final direction = assemblyDirection;
    if (locations == null || types == null || direction == null) return AssemblyPoints.silent();

    if (locations[0] != 0) {
      return AssemblyPoints.error(const StationAssemblyError('train_assembly.frontmost_bogey_at_station'));
    }

    TrackNodeLocation? location;
    final center = atBottomCenterOf(trackPosition) + (0.0, track.getElevationAtCenter(level, trackPosition, trackState), 0.0);
    final ends = track.getConnected(level, trackPosition, trackState, true, null);
    final targetOffset = direction.unitVec3;
    for (final end in ends) {
      if (mthEqual(0, targetOffset.distanceSquaredTo(vnormalize(end.getLocation() - center)))) location = end;
    }
    if (location == null) return AssemblyPoints.silent();

    final pointOffsets = <double>[];
    var iPrevious = -100;
    for (var i = 0; i < locations.length; i++) {
      final loc = locations[i];
      if (loc == -1) break;

      if (loc - iPrevious < 3) {
        return AssemblyPoints.error(StationAssemblyError('train_assembly.bogeys_too_close', [i, i + 1]));
      }

      final bogeySize = types[i]!.getWheelPointSpacing();
      pointOffsets.add(loc + .5 - bogeySize / 2);
      pointOffsets.add(loc + .5 + bogeySize / 2);
      iPrevious = loc;
    }

    final points = <TravellingPoint>[];
    final directionVec = direction.unitVec3;
    TrackGraph? graph;
    TrackNode? secondNode;

    for (var j = 0; j < assemblyLength * 2 + 40; j++) {
      final i = j / 2;
      if (points.length == pointOffsets.length) break;

      final currentLocation = location!;
      location = TrackNodeLocation.fromVec(currentLocation.getLocation() + directionVec * .5).inDimension(currentLocation.dimension);

      graph ??= Create.RAILWAYS.getGraph(null, currentLocation);
      if (graph == null) continue;
      final node = graph.locateNode(currentLocation);
      if (node == null) continue;

      for (var pointIndex = points.length; pointIndex < pointOffsets.length; pointIndex++) {
        final offset = pointOffsets[pointIndex];
        if (offset > i) break;
        final positionOnEdge = i - offset;

        final connectionsFromNode = graph.getConnectionsFrom(node);

        if (secondNode == null) {
          for (final entry in connectionsFromNode.entries) {
            final TrackEdge edge = entry.value;
            final otherNode = entry.key;
            if (edge.isTurn()) continue;
            final edgeDirection = edge.getDirection(true);
            if (mthEqual(vnormalize(edgeDirection).dot(directionVec), -1.0)) secondNode = otherNode;
          }
        }

        if (secondNode == null) return AssemblyPoints.warn('Cannot assemble: No valid starting node found');

        final edge = connectionsFromNode[secondNode];

        if (edge == null) return AssemblyPoints.warn('Cannot assemble: Missing graph edge');

        points.add(TravellingPoint.at(node, secondNode, edge, positionOnEdge, false));
      }

      secondNode = node;
    }

    if (points.length != pointOffsets.length) return AssemblyPoints.warn('Cannot assemble: Not all Points created');

    if (points.isEmpty) return AssemblyPoints.error(const StationAssemblyError('train_assembly.no_bogeys'));

    return AssemblyPoints.ok(graph!, points);
  }
}

/// `Vec3.normalize()` (the zero vector stays zero).
Vec3 vnormalize(Vec3 v) {
  final len = v.length;
  return len < 1.0e-5 ? (0.0, 0.0, 0.0) : v / len;
}

/// `Vec3.atBottomCenterOf(pos)`.
Vec3 atBottomCenterOf(Pos pos) => pos.bottomCenter;
