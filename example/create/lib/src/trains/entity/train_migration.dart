// `TrainMigration` (pure): where a travelling point of a train that lost its graph was, so that it
// can be put back on the track when the track exists again (maybe in another graph).
import '../../common/data.dart';
import '../../common/direction.dart' show mthEqual;
import '../../common/vec_helper.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_graph_location.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../util/ctag.dart';
import 'travelling_point.dart';

class TrainMigration {
  late Couple<TrackNodeLocation> locations;
  double positionOnOldEdge = 0;
  bool curve = false;
  late Vec3 fallback;

  TrainMigration();

  TrainMigration.fromPoint(TravellingPoint point) {
    final edge = point.edge!;
    final t = point.position / edge.getLength();
    fallback = edge.getPosition(null, t);
    curve = edge.isTurn();
    positionOnOldEdge = point.position;
    locations = Couple.create(point.node1!.getLocation(), point.node2!.getLocation());
  }

  TrackGraphLocation? tryMigratingTo(TrackGraph graph) {
    final node1 = graph.locateNode(locations.getFirst());
    final node2 = graph.locateNode(locations.getSecond());
    if (node1 != null && node2 != null) {
      final edge = graph.getConnectionsFrom(node1)[node2];
      if (edge != null) {
        final graphLocation = TrackGraphLocation();
        graphLocation.graph = graph;
        graphLocation.edge = locations;
        graphLocation.position = positionOnOldEdge;
        return graphLocation;
      }
    }

    if (curve) return null;

    final prevDirection = (locations.getSecond().getLocation() - locations.getFirst().getLocation()).normalized;

    for (final loc in graph.getNodes()) {
      final nodeVec = loc.getLocation();
      if (nodeVec.distanceSquaredTo(fallback) > 32 * 32) continue;

      final newNode1 = graph.locateNode(loc)!;
      for (final entry in graph.getConnectionsFrom(newNode1).entries) {
        final TrackEdge edge = entry.value;
        if (edge.isTurn()) continue;
        final TrackNode newNode2 = entry.key;
        const radius = 1 / 64.0;
        final direction = edge.getDirection(true);
        if (!mthEqual(direction.dot(prevDirection), 1)) continue;
        final intersectSphere = VecHelper.intersectSphere(nodeVec, direction, fallback, radius);
        if (intersectSphere == null) continue;
        if (!mthEqual(direction.dot((intersectSphere - nodeVec).normalized), 1)) continue;
        final edgeLength = edge.getLength();
        final position = intersectSphere.distanceTo(nodeVec) - radius;
        if (position.isNaN) continue;
        if (position < 0) continue;
        if (position > edgeLength) continue;

        final graphLocation = TrackGraphLocation();
        graphLocation.graph = graph;
        graphLocation.edge = Couple.create(loc, newNode2.getLocation());
        graphLocation.position = position;
        return graphLocation;
      }
    }

    return null;
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    tag.putBoolean('Curve', curve);
    tag.putVec3('Fallback', fallback);
    tag.putDouble('Position', positionOnOldEdge);
    tag.putCompoundList('Nodes', [locations.getFirst().write(dimensions), locations.getSecond().write(dimensions)]);
    return tag;
  }

  static TrainMigration read(CTag tag, DimensionPalette dimensions) {
    final trainMigration = TrainMigration();
    trainMigration.curve = tag.getBoolean('Curve');
    trainMigration.fallback = tag.getVec3('Fallback');
    trainMigration.positionOnOldEdge = tag.getDouble('Position');
    final nodes = tag.getCompoundList('Nodes');
    trainMigration.locations = Couple.create(
      TrackNodeLocation.read(nodes.isNotEmpty ? nodes[0] : CTag(), dimensions),
      TrackNodeLocation.read(nodes.length > 1 ? nodes[1] : CTag(), dimensions),
    );
    return trainMigration;
  }
}
