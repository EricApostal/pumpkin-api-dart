// `TrackGraphLocation` (pure): a position on an edge of a graph.
import '../../common/data.dart';
import 'track_graph.dart';
import 'track_node_location.dart';

class TrackGraphLocation {
  late TrackGraph graph;
  late Couple<TrackNodeLocation> edge;
  double position = 0;
}
