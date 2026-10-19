// `DiscoveredPath` (pure): a route the navigation found to a station.
import '../../common/data.dart';
import '../station/global_station.dart';
import 'track_node.dart';

class DiscoveredPath {
  List<Couple<TrackNode>> path;
  GlobalStation destination;
  double distance;
  double cost;

  DiscoveredPath(this.distance, this.cost, this.path, this.destination);
}
