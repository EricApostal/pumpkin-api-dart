// `TrackNode` (pure): a node of the graph. Identity equality (nodes are keys of identity maps).
import '../../common/vec_helper.dart';
import 'track_node_location.dart';

class TrackNode {
  int netId;
  Vec3 normal;
  TrackNodeLocation location;

  TrackNode(this.location, this.netId, this.normal);

  TrackNodeLocation getLocation() => location;

  int getNetId() => netId;

  Vec3 getNormal() => normal;
}
