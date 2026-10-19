// `SignalPropagator` (pure): spreads signal edge groups over the graph when signals are added or
// removed, and finds the signals a chain signal depends on.
import '../../common/data.dart';
import '../graph/edge_data.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../manager/create.dart';
import '../util/uuid.dart';
import 'signal_boundary.dart';
import 'signal_edge_group.dart';

/// A callback of the walk over boundaries: gets the node at which the boundary was reached and the
/// boundary, returns whether it changed something.
typedef BoundaryCallback = bool Function(Pair<TrackNode, SignalBoundary> pair);

abstract final class SignalPropagator {
  static void onSignalRemoved(TrackGraph graph, SignalBoundary signal) {
    // `signal.sidesToUpdate.map($ -> false)` of the Java code returns a new couple and changes nothing
    for (final front in Iterate.trueAndFalse) {
      if (signal.sidesToUpdate.get(front)) continue;
      final id = signal.groups.get(front);
      if (Create.RAILWAYS.signalEdgeGroups.remove(id) != null) Create.RAILWAYS.sync.edgeGroupRemoved(id!);

      walkSignals(
        graph,
        signal,
        front,
        (pair) {
          final node1 = pair.getFirst();
          final boundary = pair.getSecond();
          boundary.queueUpdate(node1);
          return false;
        },
        (signalData) {
          if (!signalData.hasSignalBoundaries()) {
            signalData.setSingleSignalGroup(graph, EdgeData.passiveGroup);
            return true;
          }
          return false;
        },
        false,
      );
    }
  }

  static void notifySignalsOfNewNode(TrackGraph graph, TrackNode node) {
    final frontier = <Couple<TrackNode?>>[Couple<TrackNode?>(node, null)];
    _walkSignalsFrontier(
      graph,
      frontier,
      (pair) {
        final node1 = pair.getFirst();
        final boundary = pair.getSecond();
        boundary.queueUpdate(node1);
        return false;
      },
      (signalData) {
        if (!signalData.hasSignalBoundaries()) {
          signalData.setSingleSignalGroup(graph, EdgeData.passiveGroup);
          return true;
        }
        return false;
      },
      false,
    );
  }

  static void propagateSignalGroup(TrackGraph graph, SignalBoundary signal, bool front) {
    final globalGroups = Create.RAILWAYS.signalEdgeGroups;
    final sync = Create.RAILWAYS.sync;

    final group = SignalEdgeGroup(randomUuid());
    final groupId = group.id;
    globalGroups[groupId] = group;
    signal.setGroup(front, groupId);
    sync.pointAdded(graph, signal);

    walkSignals(
      graph,
      signal,
      front,
      (pair) {
        final node1 = pair.getFirst();
        final boundary = pair.getSecond();
        final currentGroup = boundary.getGroup(node1);
        if (currentGroup != null) {
          if (globalGroups.remove(currentGroup) != null) sync.edgeGroupRemoved(currentGroup);
        }
        boundary.setGroupAndUpdate(node1, groupId);
        sync.pointAdded(graph, boundary);
        return true;
      },
      (signalData) {
        final singleSignalGroup = signalData.getSingleSignalGroup();
        if (singleSignalGroup != null) {
          if (globalGroups.remove(singleSignalGroup) != null) sync.edgeGroupRemoved(singleSignalGroup);
        }
        signalData.setSingleSignalGroup(graph, groupId);
        return true;
      },
      false,
    );

    group.resolveColor();
    sync.edgeGroupCreated(groupId, group.color);
  }

  static Map<String, bool> collectChainedSignals(TrackGraph graph, SignalBoundary signal, bool front) {
    final map = <String, bool>{};
    walkSignals(
      graph,
      signal,
      front,
      (pair) {
        final boundary = pair.getSecond();
        map[boundary.id] = !boundary.isPrimary(pair.getFirst());
        return false;
      },
      (_) => false,
      true,
    );
    return map;
  }

  static void walkSignals(
    TrackGraph graph,
    SignalBoundary signal,
    bool front,
    BoundaryCallback boundaryCallback,
    bool Function(EdgeData data) nonBoundaryCallback,
    bool forCollection,
  ) {
    final edgeLocation = signal.edgeLocation;
    final startNodes = edgeLocation.map<TrackNode?>(graph.locateNode);
    final startEdges = startNodes.mapWithParams<TrackEdge?, TrackNode?>(
      (l1, l2) => graph.getConnectionsFrom(l1)[l2],
      startNodes.swap(),
    );

    final node1 = startNodes.get(front)!;
    final node2 = startNodes.get(!front)!;
    final startEdge = startEdges.get(front);
    final oppositeEdge = startEdges.get(!front);

    if (startEdge == null) return;

    if (!forCollection) {
      notifyTrains(graph, startEdge, oppositeEdge);
      startEdge.getEdgeData().refreshIntersectingSignalGroups(graph);
      Create.RAILWAYS.sync.edgeDataChanged(graph, node1, node2, startEdge, oppositeEdge);
    }

    // Check for signal on the same edge
    final immediateBoundary = startEdge.getEdgeData().next(EdgePointType.SIGNAL, signal.getLocationOn(startEdge));
    if (immediateBoundary != null) {
      if (boundaryCallback(Pair.of(node1, immediateBoundary))) {
        startEdge.getEdgeData().refreshIntersectingSignalGroups(graph);
      }
      return;
    }

    // Search for any connected signals
    final frontier = <Couple<TrackNode?>>[Couple<TrackNode?>(node2, node1)];
    _walkSignalsFrontier(graph, frontier, boundaryCallback, nonBoundaryCallback, forCollection);
  }

  static void _walkSignalsFrontier(
    TrackGraph graph,
    List<Couple<TrackNode?>> frontier,
    BoundaryCallback boundaryCallback,
    bool Function(EdgeData data) nonBoundaryCallback,
    bool forCollection,
  ) {
    final visited = Set<TrackEdge>.identity();
    while (frontier.isNotEmpty) {
      final couple = frontier.removeAt(0);
      final currentNode = couple.getFirst()!;
      final prevNode = couple.getSecond();

      edgeWalk:
      for (final entry in graph.getConnectionsFrom(currentNode).entries) {
        final nextNode = entry.key;
        final edge = entry.value;

        if (identical(nextNode, prevNode)) continue;

        // already checked this edge
        if (!visited.add(edge)) continue;

        // chain signal: check if reachable
        if (forCollection && !graph.getConnectionsFrom(prevNode)[currentNode]!.canTravelTo(edge)) continue;

        final oppositeEdge = graph.getConnectionsFrom(nextNode)[currentNode]!;
        visited.add(oppositeEdge);

        for (final flip in Iterate.falseAndTrue) {
          final currentEdge = flip ? oppositeEdge : edge;
          final signalData = currentEdge.getEdgeData();

          // no boundary- update group of edge
          if (!signalData.hasSignalBoundaries()) {
            if (nonBoundaryCallback(signalData)) {
              notifyTrains(graph, currentEdge);
              Create.RAILWAYS.sync.edgeDataChanged(graph, currentNode, nextNode, edge, oppositeEdge);
            }
            continue;
          }

          // other/own boundary found
          final nextBoundary = signalData.next(EdgePointType.SIGNAL, 0);
          if (nextBoundary == null) continue;
          if (boundaryCallback(Pair.of(currentNode, nextBoundary))) {
            notifyTrains(graph, edge, oppositeEdge);
            currentEdge.getEdgeData().refreshIntersectingSignalGroups(graph);
            Create.RAILWAYS.sync.edgeDataChanged(graph, currentNode, nextNode, edge, oppositeEdge);
          }
          continue edgeWalk;
        }

        frontier.add(Couple<TrackNode?>(nextNode, currentNode));
      }
    }
  }

  /// `notifyTrains(graph, edges...)`: the trains of [graph] travelling on [edge1] or [edge2] must
  /// update their signal blocks.
  static void notifyTrains(TrackGraph graph, TrackEdge? edge1, [TrackEdge? edge2]) {
    for (final trackEdge in [edge1, edge2]) {
      if (trackEdge == null) continue;
      for (final train in Create.RAILWAYS.trains.values) {
        if (train.graph != graph) continue;
        if (train.updateSignalBlocks) continue;
        train.forEachTravellingPoint((tp) {
          if (identical(tp.edge, trackEdge)) train.updateSignalBlocks = true;
        });
      }
    }
  }
}
