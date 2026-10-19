// `TrainRelocator` (server part): moves a whole train onto a track it was clicked at, after
// probing the way of every wheel point along the target edge. The client half of Java (the hover
// outline, `relocateClient`, `clientTick`, the tooltip) is not ported.
import '../../common/data.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import 'train.dart';
import 'train_level.dart';
import 'travelling_point.dart';
import '../graph/track_graph_helper.dart';
import '../graph/track_node.dart';
import '../track/bezier_track_point_location.dart';
import '../track/i_track_block.dart';
import '../track/track_level.dart';

abstract final class TrainRelocator {
  /// `relocate(train, level, pos, bezier, bezierDirection, lookAngle, simulate)`. [trainLevel] is
  /// the level of the train (for `findCollidingTrain`), `null` when it is not available.
  static bool relocate(
    Train train,
    TrackLevel level,
    TrainLevel? trainLevel,
    Pos pos,
    BezierTrackPointLocation? bezier,
    bool bezierDirection,
    Vec3 lookAngle,
    bool simulate,
  ) {
    final blockState = level.stateAt(pos);
    final track = TrackBlockRegistry.ofState(blockState);
    if (track == null) return false;

    final nearestTrackAxis = track.getNearestTrackAxis(
      level,
      pos,
      blockState,
      lookAngle,
    );
    final graphLocation = bezier != null
        ? TrackGraphHelper.getBezierGraphLocationAt(
            level,
            pos,
            bezierDirection ? AxisDirection.positive : AxisDirection.negative,
            bezier,
          )
        : TrackGraphHelper.getGraphLocationAt(
            level,
            pos,
            nearestTrackAxis.getSecond(),
            nearestTrackAxis.getFirst(),
          );
    if (graphLocation == null) return false;

    final graph = graphLocation.graph;
    final node1 = graph.locateNode(graphLocation.edge.getFirst());
    final node2 = graph.locateNode(graphLocation.edge.getSecond());
    if (node1 == null || node2 == null) return false;
    final edge = graph.getConnectionsFrom(node1)[node2];
    if (edge == null) return false;

    final probe = TravellingPoint.at(
      node1,
      node2,
      edge,
      graphLocation.position,
      false,
    );
    final ignoreSignals = probe.ignoreEdgePoints();
    final ignoreTurns = probe.ignoreTurns();
    final recordedLocations = <Pair<Couple<TrackNode>, double>>[];
    final recordedVecs = <Vec3>[];

    void record(TravellingPoint point) {
      recordedLocations.add(
        Pair(Couple.create(point.node1!, point.node2!), point.position),
      );
      recordedVecs.add(point.getPosition(graph));
    }

    final steer = probe.steer(
      SteerDirection.none,
      track.getUpNormal(level, pos, blockState),
    );
    var blocked = false;
    var portal = false;
    var blockingIndex = 0;

    train.forEachTravellingPointBackwards((tp, d) {
      if (blocked) return;
      probe.travel(graph, d, steer, ignoreSignals, ignoreTurns, (locations) {
        portal = true;
        return true;
      });
      record(probe);
      if (probe.blocked || portal) {
        blocked = true;
        return;
      }
      blockingIndex++;
    });

    for (var i = 0; i < recordedVecs.length - 1; i++) {
      final vec1 = recordedVecs[i];
      final vec2 = recordedVecs[i + 1];
      final blocking = i >= blockingIndex - 1;
      final collided =
          !blocked &&
          trainLevel != null &&
          train.findCollidingTrain(trainLevel, vec1, vec2, level.dimension) !=
              null;
      if (collided || blocking) return false;
    }

    if (blocked) return false;
    if (simulate) return true;

    train.leaveStation();
    train.derailed = false;
    train.navigation.waitingForSignal = null;
    train.occupiedSignalBlocks.clear();
    train.graph = graph;
    train.speed = 0;
    train.migratingPoints.clear();
    train.cancelStall();

    if (train.navigation.destination != null) {
      train.navigation.cancelNavigation();
    }

    train.forEachTravellingPoint((tp) {
      final last = recordedLocations.removeLast();
      tp.node1 = last.getFirst().getFirst();
      tp.node2 = last.getFirst().getSecond();
      tp.position = last.getSecond();
      tp.edge = graph.getConnectionsFrom(tp.node1)[tp.node2];
    });

    for (final carriage in train.carriages) {
      carriage.updateContraptionAnchors();
    }

    train.status.successfulMigration();
    train.collectInitiallyOccupiedSignalBlocks();
    return true;
  }
}
