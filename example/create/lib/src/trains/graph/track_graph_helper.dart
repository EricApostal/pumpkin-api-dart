// `TrackGraphHelper` (pure): finds the position on the graph that belongs to a point on a track block.
import '../../common/common.dart';
import '../manager/create.dart';
import '../track/bezier_track_point_location.dart';
import '../track/i_track_block.dart';
import '../track/track_level.dart';
import 'track_graph.dart';
import 'track_graph_location.dart';
import 'track_node.dart';
import 'track_node_location.dart';

abstract final class TrackGraphHelper {
  static TrackGraphLocation? getGraphLocationAt(TrackLevel level, Pos pos, AxisDirection targetDirection, Vec3 targetAxis) {
    final trackBlockState = level.stateAt(pos);
    final track = TrackBlockRegistry.ofState(trackBlockState);
    if (track == null) return null;

    final axis = targetAxis * targetDirection.step;
    final length = axis.length;
    TrackGraph? graph;

    // Case 1: Centre of block lies on a node

    final location = TrackNodeLocation.fromVec(
      pos.bottomCenter + (0.0, track.getElevationAtCenter(level, pos, trackBlockState), 0.0),
    ).inDimension(level.dimension);
    graph = Create.RAILWAYS.sided(level).getGraph(level, location);
    if (graph != null) {
      final node = graph.locateNode(location);
      if (node != null) {
        final connectionsFrom = graph.getConnectionsFrom(node);
        for (final entry in connectionsFrom.entries) {
          final backNode = entry.key;
          final direction = entry.value.getDirection(true);
          if ((direction * length).distanceSquaredTo(axis * -1) > 1 / 4096.0) continue;

          final graphLocation = TrackGraphLocation();
          graphLocation.edge = Couple.create(node.getLocation(), backNode.getLocation());
          graphLocation.position = 0;
          graphLocation.graph = graph;
          return graphLocation;
        }
      }
    }

    // Case 2: Center of block is between two nodes

    final ends = track.getConnected(level, pos, trackBlockState, true, null);
    final start = pos.bottomCenter + (0.0, track.getElevationAtCenter(level, pos, trackBlockState), 0.0);

    TrackNode? frontNode;
    TrackNode? backNode;
    var position = 0.0;
    var singleTrackPiece = true;

    for (var current in ends) {
      final offset = (current.getLocation() - start).normalized * length;

      final compareOffset = offset.multiplyBy((1, 0, 1)).normalized;
      final forward = compareOffset.distanceSquaredTo(axis.multiplyBy((-1, 0, -1)).normalized) < 1 / 4096.0;
      final backwards = compareOffset.distanceSquaredTo(axis.multiplyBy((1, 0, 1)).normalized) < 1 / 4096.0;

      if (!forward && !backwards) continue;

      DiscoveredLocation? previous;
      var distance = 0.0;

      for (var i = 0; i < 100 && distance < 32; i++) {
        final loc = current;
        graph ??= Create.RAILWAYS.sided(level).getGraph(level, loc);

        if (graph == null || graph.locateNode(loc) == null) {
          singleTrackPiece = false;
          final list = ITrackBlock.walkConnectedTracks(level, loc, true);
          for (final discoveredLocation in list) {
            if (identical(discoveredLocation, previous)) continue;
            final diff = discoveredLocation.getLocation() - loc.getLocation();
            if ((forward ? axis * -1 : axis).distanceSquaredTo(diff.normalized * length) > 1 / 4096.0) continue;

            previous = current;
            current = discoveredLocation;
            distance += diff.length;
            break;
          }
          continue;
        }

        final node = graph.locateNode(loc);
        if (forward) frontNode = node;
        if (backwards) {
          backNode = node;
          position = distance + axis.length / 2;
        }
        break;
      }
    }

    if (frontNode == null || backNode == null) return null;

    if (singleTrackPiece) {
      position = frontNode.getLocation().getLocation().distanceTo(backNode.getLocation().getLocation()) / 2.0;
    }

    final graphLocation = TrackGraphLocation();
    graphLocation.edge = Couple.create(backNode.getLocation(), frontNode.getLocation());
    graphLocation.position = position;
    graphLocation.graph = graph!;
    return graphLocation;
  }

  static TrackGraphLocation? getBezierGraphLocationAt(
    TrackLevel level,
    Pos pos,
    AxisDirection targetDirection,
    BezierTrackPointLocation targetBezier,
  ) {
    final state = level.stateAt(pos);

    final track = TrackBlockRegistry.ofState(state);
    if (track == null) return null;
    final trackBE = level.getTrackBlockEntity(pos);
    if (trackBE == null) return null;
    final bc = trackBE.getConnections()[targetBezier.getCurveTarget()];
    if (bc == null || !bc.isPrimary()) return null;

    final targetLoc = TrackNodeLocation.fromVec(bc.starts.getSecond()).inDimension(level.dimension);
    if (bc.smoothing != null) targetLoc.yOffsetPixels = bc.smoothing!.getSecond();

    for (final location in track.getConnected(level, pos, state, true, null)) {
      final graph = Create.RAILWAYS.sided(level).getGraph(level, location);
      if (graph == null) continue;
      final targetNode = graph.locateNode(targetLoc);
      if (targetNode == null) continue;
      final node = graph.locateNode(location);
      final edge = graph.getConnectionsFrom(node)[targetNode];
      if (edge == null) continue;

      final graphLocation = TrackGraphLocation();
      graphLocation.graph = graph;
      graphLocation.edge = Couple.create(location, targetLoc);
      graphLocation.position = (targetBezier.getSegment() + 1) / 2.0;
      if (targetDirection == AxisDirection.positive) {
        graphLocation.edge = graphLocation.edge.swap();
        graphLocation.position = edge.getLength() - graphLocation.position;
      }

      return graphLocation;
    }

    return null;
  }
}
