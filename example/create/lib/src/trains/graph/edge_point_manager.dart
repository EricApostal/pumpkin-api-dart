// `EdgePointManager` (pure): puts edge points on the edges of a graph and takes them off again.
import '../../common/data.dart';
import '../manager/create.dart';
import '../signal/track_edge_point.dart';
import 'edge_point_type.dart';
import 'track_edge.dart';
import 'track_graph.dart';
import 'track_node.dart';

abstract final class EdgePointManager {
  static void onEdgePointAdded<T extends TrackEdgePoint>(TrackGraph graph, T point, EdgePointType<T> type) {
    final edgeLocation = point.edgeLocation;
    final startNodes = edgeLocation.map<TrackNode?>(graph.locateNode);
    final startEdges = startNodes.mapWithParams<TrackEdge?, TrackNode?>(
      (l1, l2) => graph.getConnectionsFrom(l1)[l2],
      startNodes.swap(),
    );

    for (final front in Iterate.trueAndFalse) {
      final node1 = startNodes.get(front)!;
      final node2 = startNodes.get(!front)!;
      final startEdge = startEdges.get(front)!;
      startEdge.getEdgeData().addPoint(graph, point);
      Create.RAILWAYS.sync.edgeDataChanged(graph, node1, node2, startEdge);
    }
  }

  static void onEdgePointRemoved<T extends TrackEdgePoint>(TrackGraph graph, T point, EdgePointType<T> type) {
    point.onRemoved(graph);
    final edgeLocation = point.edgeLocation;
    final startNodes = edgeLocation.map<TrackNode?>(graph.locateNode);
    startNodes.forEachWithParams<TrackNode?>((l1, l2) {
      final trackEdge = graph.getConnectionsFrom(l1)[l2];
      if (trackEdge == null) return;
      trackEdge.getEdgeData().removePoint(graph, point);
      Create.RAILWAYS.sync.edgeDataChanged(graph, l1!, l2!, trackEdge);
    }, startNodes.swap());
  }
}
