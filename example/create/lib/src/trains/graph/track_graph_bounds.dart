// `TrackGraphBounds` (pure): the box around the nodes of a graph in one dimension and its beziers.
import '../../common/bounds.dart';
import '../track/bezier_connection.dart';
import 'track_graph.dart';
import 'track_node.dart';

class TrackGraphBounds {
  Aabb? box;
  List<BezierConnection> beziers = [];

  TrackGraphBounds(TrackGraph graph, String dimension) {
    for (final node in graph.nodes.values) {
      if (node.location.dimension != dimension) continue;
      _include(node);
      final connections = graph.getConnectionsFrom(node);
      for (final edge in connections.values) {
        final turn = edge.turn;
        if (turn != null && turn.isPrimary()) beziers.add(turn);
      }
    }

    box = box?.inflate(2);
  }

  void _include(TrackNode node) {
    final v = node.location.getLocation();
    final aabb = Aabb.between(v, v);
    box = box == null ? aabb : box!.minmax(aabb);
  }
}
