// `TrackPropagator` (pure): builds, merges and splits the track graphs when a track block is
// placed or removed. A line by line port: remove the nodes the new rail touches, merge the graphs
// it connects, find the first graph node candidate nearby and walk out from it.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../manager/create.dart';
import '../signal/signal_propagator.dart';
import 'i_track_block.dart';

class _FrontierEntry {
  DiscoveredLocation? prevNode;
  DiscoveredLocation currentNode;
  DiscoveredLocation? parentNode;

  _FrontierEntry(DiscoveredLocation? parent, DiscoveredLocation? previousNode, DiscoveredLocation location)
    : parentNode = parent,
      prevNode = previousNode,
      currentNode = location;
}

abstract final class TrackPropagator {
  /// `NeoForge.EVENT_BUS.post(new TrackGraphMergeEvent(other, graph))`: listeners of the merge of
  /// graph [other] into [graph].
  static final List<void Function(TrackGraph other, TrackGraph graph)> graphMergeListeners = [];

  /// `onRailRemoved(reader, pos, state)`.
  static void onRailRemoved(BlockGetter reader, Pos pos, BState state) {
    final track = TrackBlockRegistry.ofState(state);
    if (track == null) return;

    final ends = track.getConnected(reader, pos, state, false, null);
    final manager = Create.RAILWAYS;
    final sync = manager.sync;

    // 1. Remove any nodes this rail was part of

    for (final removedLocation in ends) {
      final intersecting = manager.getGraphs(reader, removedLocation);
      for (final foundGraph in intersecting) {
        final removedNode = foundGraph.locateNode(removedLocation);
        if (removedNode == null) continue;
        foundGraph.removeNode(reader, removedLocation);
        sync.nodeRemoved(foundGraph, removedNode);
        if (!foundGraph.isEmpty()) continue;
        manager.removeGraphAndGroup(foundGraph);
        sync.graphRemoved(foundGraph);
      }
    }

    final positionsToUpdate = <Pos>{};
    for (final removedEnd in ends) {
      positionsToUpdate.addAll(removedEnd.allAdjacent());
    }

    // 2. Re-run railAdded for any track that was disconnected from this track

    final toUpdate = <TrackGraph>{};
    for (final blockPos in positionsToUpdate) {
      if (blockPos != pos) {
        final onRailAdded = TrackPropagator.onRailAdded(reader, blockPos, reader.stateAt(blockPos));
        if (onRailAdded != null) toUpdate.add(onRailAdded);
      }
    }

    // 3. Ensure any affected graph gets checked for segmentation

    for (final railGraph in toUpdate) {
      manager.updateSplitGraph(reader, railGraph);
    }

    manager.markTracksDirty();
  }

  /// `onRailAdded(reader, pos, state)`: the graph the rail belongs to afterwards, `null` for
  /// non-track blocks.
  static TrackGraph? onRailAdded(BlockGetter reader, Pos pos, BState state) {
    final track = TrackBlockRegistry.ofState(state);
    if (track == null) return null;

    // 1. Remove all immediately reachable node locations

    final manager = Create.RAILWAYS;
    final sync = manager.sync;
    final frontier = <_FrontierEntry>[];
    final visited = <DiscoveredLocation>{};
    final connectedGraphs = <TrackGraph>{};
    _addInitialEndsOf(reader, pos, state, track, frontier, false);

    var emergencyExit = 1000;
    while (frontier.isNotEmpty) {
      if (emergencyExit-- == 0) break;

      final entry = frontier.removeAt(0);
      final intersecting = manager.getGraphs(reader, entry.currentNode);
      for (final graph in intersecting) {
        final node = graph.locateNode(entry.currentNode);
        graph.removeNode(reader, entry.currentNode);
        sync.nodeRemoved(graph, node!);
        connectedGraphs.add(graph);
      }

      if (intersecting.isNotEmpty) continue;

      final ends = ITrackBlock.walkConnectedTracks(reader, entry.currentNode, false);
      if (entry.prevNode != null) ends.remove(entry.prevNode);
      _continueSearch(frontier, visited, entry, ends);
    }

    frontier.clear();
    visited.clear();
    TrackGraph? graph;

    // Remove empty graphs
    for (final railGraph in connectedGraphs.toList()) {
      if (!railGraph.isEmpty() || connectedGraphs.length == 1) continue;
      manager.removeGraphAndGroup(railGraph);
      sync.graphRemoved(railGraph);
      connectedGraphs.remove(railGraph);
    }

    // Merge graphs if more than 1
    if (connectedGraphs.length > 1) {
      for (final other in connectedGraphs) {
        if (graph == null) {
          graph = other;
        } else {
          for (final listener in graphMergeListeners) {
            listener(other, graph);
          }
          other.transferAll(graph);
          manager.removeGraphAndGroup(other);
          sync.graphRemoved(other);
        }
      }
    } else if (connectedGraphs.length == 1) {
      graph = connectedGraphs.first;
    } else {
      graph = TrackGraph();
      manager.putGraphWithDefaultGroup(graph);
    }

    final g = graph!;
    DiscoveredLocation? startNode;

    // 2. Find the first graph node candidate nearby

    _addInitialEndsOf(reader, pos, state, track, frontier, true);

    emergencyExit = 1000;
    while (frontier.isNotEmpty) {
      if (emergencyExit-- == 0) break;

      final entry = frontier.removeAt(0);
      final ends = ITrackBlock.walkConnectedTracks(reader, entry.currentNode, false);
      final first = entry.prevNode == null;
      if (!first) ends.remove(entry.prevNode);
      if (isValidGraphNodeLocation(entry.currentNode, ends, first)) {
        startNode = entry.currentNode;
        break;
      }

      _continueSearch(frontier, visited, entry, ends);
    }

    frontier.clear();
    final addedNodes = <TrackNode>{};
    if (startNode == null) return g;
    g.createNodeIfAbsent(startNode);
    frontier.add(_FrontierEntry(startNode, null, startNode));

    // 3. Build up the graph via all connected nodes

    emergencyExit = 1000;
    while (frontier.isNotEmpty) {
      if (emergencyExit-- == 0) break;

      final entry = frontier.removeAt(0);
      var parentNode = entry.parentNode!;
      final ends = ITrackBlock.walkConnectedTracks(reader, entry.currentNode, false);
      final first = entry.prevNode == null;
      if (!first) ends.remove(entry.prevNode);

      if (isValidGraphNodeLocation(entry.currentNode, ends, first) && !identical(entry.currentNode, startNode)) {
        final nodeIsNew = g.createNodeIfAbsent(entry.currentNode);
        g.connectNodes(reader, parentNode, entry.currentNode, entry.currentNode.getTurn());
        addedNodes.add(g.locateNode(entry.currentNode)!);
        parentNode = entry.currentNode;
        if (!nodeIsNew) continue;
      }

      _continueSearchWithParent(frontier, entry, parentNode, ends);
    }

    manager.markTracksDirty();
    for (final trackNode in addedNodes) {
      SignalPropagator.notifySignalsOfNewNode(g, trackNode);
    }
    return g;
  }

  static void _addInitialEndsOf(
    BlockGetter reader,
    Pos pos,
    BState state,
    ITrackBlock track,
    List<_FrontierEntry> frontier,
    bool ignoreTurns,
  ) {
    for (final initial in track.getConnected(reader, pos, state, ignoreTurns, null)) {
      frontier.add(_FrontierEntry(null, null, initial));
    }
  }

  static void _continueSearch(
    List<_FrontierEntry> frontier,
    Set<DiscoveredLocation> visited,
    _FrontierEntry entry,
    List<DiscoveredLocation> ends,
  ) {
    for (final location in ends) {
      if (visited.add(location)) frontier.add(_FrontierEntry(null, entry.currentNode, location));
    }
  }

  static void _continueSearchWithParent(
    List<_FrontierEntry> frontier,
    _FrontierEntry entry,
    DiscoveredLocation parentNode,
    List<DiscoveredLocation> ends,
  ) {
    for (final location in ends) {
      frontier.add(_FrontierEntry(parentNode, entry.currentNode, location));
    }
  }

  /// `isValidGraphNodeLocation(location, next, first)`.
  static bool isValidGraphNodeLocation(DiscoveredLocation location, List<DiscoveredLocation> next, bool first) {
    final size = next.length - (first ? 1 : 0);
    if (size != 1) return true;
    if (location.shouldForceNode()) return true;
    if (location.differentMaterials()) return true;
    if (next.any((dl) => dl.shouldForceNode())) return true;

    final direction = location.getDirection();
    if (direction != null && next.any((dl) => dl.notInLineWith(direction))) return true;

    final vec = location.getLocation();
    final centeredX = !mthEqual(vec.x, javaRound(vec.x).toDouble());
    final centeredZ = !mthEqual(vec.z, javaRound(vec.z).toDouble());
    if (centeredX && !centeredZ) return javaRound(vec.z) % 16 == 0;
    return javaRound(vec.x) % 16 == 0;
  }
}
