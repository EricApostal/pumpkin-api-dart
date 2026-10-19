// `TrackGraph` (pure): the nodes, edges and edge points of one connected rail network.
//
// Java -> Dart notes: `Level` / `LevelAccessor` parameters that the pure code only passes on are
// `Object?` (a world, a [Lvl] or nothing); dimensions are world ids ([String]); uuids are canonical
// text; the registries argument of `write` / `read` does not exist.
import 'dart:math' as math;

import '../../common/data.dart';
import '../../common/direction.dart' show toFloat;
import '../../common/vec_helper.dart';
import '../manager/create.dart';
import '../signal/track_edge_point.dart';
import '../track/bezier_connection.dart';
import '../util/ctag.dart';
import '../util/uuid.dart';
import 'dimension_palette.dart';
import 'edge_point_manager.dart';
import 'edge_point_storage.dart';
import 'edge_point_type.dart';
import 'graph_color.dart';
import 'track_edge.dart';
import 'track_edge_intersection.dart';
import 'track_graph_bounds.dart';
import 'track_node.dart';
import 'track_node_location.dart';

class TrackGraph {
  static int graphNetIdGenerator = 0;
  static int nodeNetIdGenerator = 0;

  late String id;

  /// `Color.getRGB()` of the graph colour (opaque ARGB).
  late int color;

  Map<TrackNodeLocation, TrackNode> nodes = {};
  Map<int, TrackNode> nodesById = {};
  Map<TrackNode, Map<TrackNode, TrackEdge>> connectionsByNode = Map.identity();
  EdgePointStorage edgePoints = EdgePointStorage();
  Map<String, TrackGraphBounds> bounds = {};

  List<TrackEdge> deferredIntersectionUpdates = [];

  int netId = nextGraphId();
  int checksum = 0;

  TrackGraph([String? graphID]) {
    setId(graphID ?? randomUuid());
  }

  //

  void addPoint<T extends TrackEdgePoint>(EdgePointType<T> type, T point) {
    edgePoints.put(type, point);
    EdgePointManager.onEdgePointAdded(this, point, type);
    Create.RAILWAYS.sync.pointAdded(this, point);
    markDirty();
  }

  T? getPoint<T extends TrackEdgePoint>(EdgePointType<T> type, String id) => edgePoints.get(type, id);

  List<T> getPoints<T extends TrackEdgePoint>(EdgePointType<T> type) => edgePoints.values(type);

  T? removePoint<T extends TrackEdgePoint>(EdgePointType<T> type, String id) {
    final removed = edgePoints.remove(type, id);
    if (removed == null) return null;
    EdgePointManager.onEdgePointRemoved(this, removed, type);
    Create.RAILWAYS.sync.pointRemoved(this, removed);
    markDirty();
    return removed;
  }

  void tickPoints(bool preTrains) {
    edgePoints.tick(this, preTrains);
  }

  //

  /// `getBounds(level)`: [dimension] is the world id of the level.
  TrackGraphBounds getBounds(String dimension) => bounds.putIfAbsent(dimension, () => TrackGraphBounds(this, dimension));

  void invalidateBounds() {
    checksum = 0;
    bounds.clear();
  }

  //

  Iterable<TrackNodeLocation> getNodes() => nodes.keys;

  /// `locateNode(level, position)`: [dimension] is the world id of the level.
  TrackNode? locateNodeAt(String dimension, Vec3 position) =>
      locateNode(TrackNodeLocation.fromVec(position).inDimension(dimension));

  TrackNode? locateNode(TrackNodeLocation position) => nodes[position];

  TrackNode? getNode(int netId) => nodesById[netId];

  bool createNodeIfAbsent(DiscoveredLocation location) {
    if (!addNodeIfAbsent(TrackNode(location, nextNodeId(), location.normal ?? vec3Zero))) return false;
    final newNode = nodes[location]!;
    Create.RAILWAYS.sync.nodeAdded(this, newNode);
    invalidateBounds();
    markDirty();
    return true;
  }

  void loadNode(TrackNodeLocation location, int netId, Vec3 normal) {
    addNode(TrackNode(location, netId, normal));
  }

  void addNode(TrackNode node) {
    final location = node.getLocation();
    if (nodes.containsKey(location)) removeNode(null, location);
    nodes[location] = node;
    nodesById[node.getNetId()] = node;
  }

  bool addNodeIfAbsent(TrackNode node) {
    if (nodes.containsKey(node.getLocation())) return false;
    nodes[node.getLocation()] = node;
    nodesById[node.getNetId()] = node;
    return true;
  }

  /// `removeNode(level, location)`; [level] may be `null`.
  bool removeNode(Object? level, TrackNodeLocation location) {
    final removed = nodes.remove(location);
    if (removed == null) return false;

    final trains = Create.RAILWAYS.trains;
    for (final train in trains.values.toList()) {
      if (train.graph != this) continue;
      if (train.isTravellingOn(removed)) train.detachFromTracks();
    }

    nodesById.remove(removed.netId);
    invalidateBounds();

    if (!connectionsByNode.containsKey(removed)) return true;

    final connections = connectionsByNode.remove(removed)!;
    for (final entry in connections.entries.toList()) {
      final trackEdge = entry.value;
      final edgeData = trackEdge.getEdgeData();
      for (final point in edgeData.getPoints().toList()) {
        if (level != null) point.invalidate(level);
        edgePoints.remove(point.getType(), point.getId());
      }
      if (level != null) {
        final otherNode = entry.key;
        for (final intersection in edgeData.getIntersections().toList()) {
          final target = intersection.target;
          final graph = Create.RAILWAYS.getGraph(level, target.getFirst());
          graph?.removeIntersection(intersection, removed, otherNode);
        }
      }
    }

    for (final railNode in connections.keys) {
      if (connectionsByNode.containsKey(railNode)) connectionsByNode[railNode]!.remove(removed);
    }

    return true;
  }

  void removeIntersection(TrackEdgeIntersection intersection, TrackNode targetNode1, TrackNode targetNode2) {
    final node1 = locateNode(intersection.target.getFirst());
    final node2 = locateNode(intersection.target.getSecond());
    if (node1 == null || node2 == null) return;

    final from1 = getConnectionsFrom(node1);
    final edge1 = from1[node2];
    edge1?.getEdgeData().removeIntersection(this, intersection.id);

    final from2 = getConnectionsFrom(node2);
    final edge2 = from2[node1];
    edge2?.getEdgeData().removeIntersection(this, intersection.id);
  }

  static int nextNodeId() => ++nodeNetIdGenerator;

  static int nextGraphId() => ++graphNetIdGenerator;

  void transferAll(TrackGraph toOther) {
    nodes.forEach((loc, node) {
      if (toOther.addNodeIfAbsent(node)) Create.RAILWAYS.sync.nodeAdded(toOther, node);
    });

    for (final e1 in connectionsByNode.entries.toList()) {
      final node1 = e1.key;
      for (final e2 in e1.value.entries.toList()) {
        final node2 = e2.key;
        final edge = e2.value;
        final n1 = toOther.locateNode(node1.location);
        final n2 = toOther.locateNode(node2.location);
        if (n1 == null || n2 == null) continue;
        if (toOther.putConnection(n1, n2, edge)) {
          Create.RAILWAYS.sync.edgeAdded(toOther, n1, n2, edge);
          Create.RAILWAYS.sync.edgeDataChanged(toOther, n1, n2, edge);
        }
      }
    }

    edgePoints.transferAll(toOther, toOther.edgePoints);
    nodes.clear();
    connectionsByNode.clear();
    toOther.invalidateBounds();

    final trains = Create.RAILWAYS.trains;
    for (final train in trains.values) {
      if (train.graph != this) continue;
      train.graph = toOther;
    }
  }

  /// `findDisconnectedGraphs(level, splitSubGraphs)`: [splitSubGraphs] maps a node net id to the
  /// `(netId, graph id)` the graph that contains it gets (client side).
  Set<TrackGraph> findDisconnectedGraphs(Object? level, Map<int, Pair<int, String>>? splitSubGraphs) {
    final dicovered = <TrackGraph>{};
    final vertices = <TrackNodeLocation>{...nodes.keys};
    final frontier = <TrackNodeLocation>[];
    TrackGraph? target;

    while (vertices.isNotEmpty) {
      if (target != null) dicovered.add(target);

      final start = vertices.first;
      frontier.add(start);
      vertices.remove(start);

      while (frontier.isNotEmpty) {
        final current = frontier.removeAt(0);
        final currentNode = locateNode(current)!;

        final connections = getConnectionsFrom(currentNode);
        for (final connected in connections.keys) {
          if (vertices.remove(connected.getLocation())) frontier.add(connected.getLocation());
        }

        if (target != null) {
          if (splitSubGraphs != null && splitSubGraphs.containsKey(currentNode.getNetId())) {
            final ids = splitSubGraphs[currentNode.getNetId()]!;
            target.setId(ids.getSecond());
            target.netId = ids.getFirst();
          }
          transfer(level, currentNode, target);
        }
      }

      frontier.clear();
      target = TrackGraph();
    }

    return dicovered;
  }

  void setId(String id) {
    this.id = id;
    color = rainbowColor(javaRandomNextInt(uuidLeastSignificant(id)));
  }

  void setNetId(int id) {
    netId = id;
  }

  int getChecksum() {
    if (checksum == 0) {
      var sum = 0;
      for (final n in nodes.values) {
        sum += n.getNetId();
      }
      checksum = sum.toSigned(32);
    }
    return checksum;
  }

  void transfer(Object? level, TrackNode node, TrackGraph target) {
    target.addNode(node);
    target.invalidateBounds();

    final nodeLoc = node.getLocation();
    final connections = getConnectionsFrom(node);
    final trains = Create.RAILWAYS.sided(level).trains;

    if (connections.isNotEmpty) {
      target.connectionsByNode[node] = connections;
      for (final entry in connections.values) {
        final edgeData = entry.getEdgeData();
        for (final trackEdgePoint in edgeData.getPoints()) {
          target.edgePoints.put(trackEdgePoint.getType(), trackEdgePoint);
          edgePoints.remove(trackEdgePoint.getType(), trackEdgePoint.getId());
        }
      }
    }

    if (level != null) {
      for (final train in trains.values) {
        if (train.graph != this) continue;
        if (!train.isTravellingOn(node)) continue;
        train.graph = target;
      }
    }

    nodes.remove(nodeLoc);
    nodesById.remove(node.getNetId());
    connectionsByNode.remove(node);
    invalidateBounds();
  }

  bool isEmpty() => nodes.isEmpty;

  /// The edges leaving [node] (an empty map when there are none).
  Map<TrackNode, TrackEdge> getConnectionsFrom(TrackNode? node) {
    if (node == null) return <TrackNode, TrackEdge>{};
    return connectionsByNode[node] ?? <TrackNode, TrackEdge>{};
  }

  TrackEdge? getConnection(Couple<TrackNode?> nodes) => getConnectionsFrom(nodes.getFirst())[nodes.getSecond()];

  void connectNodes(Object? reader, DiscoveredLocation location, DiscoveredLocation location2, BezierConnection? turn) {
    final node1 = nodes[location]!;
    final node2 = nodes[location2]!;

    final bezier = turn != null;
    final material = bezier ? turn.getMaterial() : location2.materialAValue!;
    final edge = TrackEdge(node1, node2, turn, material);
    final edge2 = TrackEdge(node2, node1, bezier ? turn.secondary() : null, material);

    for (final graph in Create.RAILWAYS.trackNetworks.values) {
      for (final otherNode1 in graph.nodes.values) {
        final connections = graph.connectionsByNode[otherNode1];
        if (connections == null) continue;
        for (final entry in connections.entries) {
          final otherNode2 = entry.key;
          final otherEdge = entry.value;

          if (graph == this) {
            if (otherNode1 == node1 || otherNode2 == node1 || otherNode1 == node2 || otherNode2 == node2) continue;
          }

          if (identical(edge, otherEdge)) continue;
          if (otherEdge.isInterDimensional() || edge.isInterDimensional()) continue;
          if (node1.location.dimension != otherNode1.location.dimension) continue;
          if (!bezier && !otherEdge.isTurn()) continue;
          if (otherEdge.isTurn() && otherEdge.turn!.isPrimary()) continue;

          final intersections = edge.getIntersection(node1, node2, otherEdge, otherNode1, otherNode2);

          final id = randomUuid();
          for (final intersection in intersections) {
            final s = intersection[0];
            final t = intersection[1];
            edge.edgeData.addIntersection(this, id, s, otherNode1, otherNode2, t);
            edge2.edgeData.addIntersection(this, id, edge.getLength() - s, otherNode1, otherNode2, t);
            otherEdge.edgeData.addIntersection(graph, id, t, node1, node2, s);
            final otherEdge2 = graph.getConnection(Couple.create(otherNode2, otherNode1));
            otherEdge2?.edgeData.addIntersection(graph, id, otherEdge.getLength() - t, node1, node2, s);
          }
        }
      }
    }

    putConnection(node1, node2, edge);
    putConnection(node2, node1, edge2);
    Create.RAILWAYS.sync.edgeAdded(this, node1, node2, edge);
    Create.RAILWAYS.sync.edgeAdded(this, node2, node1, edge2);

    markDirty();
  }

  void disconnectNodes(TrackNode node1, TrackNode node2) {
    final map1 = connectionsByNode[node1];
    final map2 = connectionsByNode[node2];
    map1?.remove(node2);
    map2?.remove(node1);
  }

  bool putConnection(TrackNode node1, TrackNode node2, TrackEdge edge) {
    final connections = connectionsByNode.putIfAbsent(node1, () => Map.identity());
    final existing = connections[node2];
    if (existing != null && existing.getEdgeData().hasPoints()) return false;
    connections[node2] = edge;
    return existing == null;
  }

  /// `distanceToLocationSqr(level, location)`: [dimension] is the world id of the level.
  double distanceToLocationSqr(String dimension, Vec3 location) {
    var nearest = 3.4028234663852886e38;
    for (final tnl in nodes.keys) {
      if (tnl.dimension != dimension) continue;
      nearest = math.min(nearest, toFloat(tnl.getLocation().distanceSquaredTo(location)));
    }
    return nearest;
  }

  void deferIntersectionUpdate(TrackEdge edge) {
    deferredIntersectionUpdates.add(edge);
  }

  void resolveIntersectingEdgeGroups(Object? level) {
    for (final edge in deferredIntersectionUpdates.toList()) {
      if (!connectionsByNode.containsKey(edge.node1) || !identical(edge, connectionsByNode[edge.node1]![edge.node2])) {
        continue;
      }
      final edgeData = edge.getEdgeData();
      for (final intersection in edgeData.getIntersections()) {
        final groupId = edgeData.getGroupAtPosition(this, intersection.location);
        final target = intersection.target;
        final graph = Create.RAILWAYS.getGraph(level, target.getFirst());
        if (graph == null) continue;

        final node1 = graph.locateNode(target.getFirst());
        final node2 = graph.locateNode(target.getSecond());
        final connectionsFrom = graph.getConnectionsFrom(node1);
        final otherEdge = connectionsFrom[node2];
        if (otherEdge == null) continue;
        final otherGroupId = otherEdge.getEdgeData().getGroupAtPosition(graph, intersection.targetLocation);

        final group = Create.RAILWAYS.signalEdgeGroups[groupId];
        final otherGroup = Create.RAILWAYS.signalEdgeGroups[otherGroupId];
        if (group == null || otherGroup == null || groupId == null || otherGroupId == null) continue;

        intersection.groupId = groupId;
        group.putIntersection(intersection.id, otherGroupId);
        otherGroup.putIntersection(intersection.id, groupId);
      }
    }
    deferredIntersectionUpdates.clear();
  }

  void markDirty() {
    Create.RAILWAYS.markTracksDirty();
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    tag.putUuid('Id', id);
    tag.putInt('Color', color);

    final indexTracker = Map<TrackNode, int>.identity();
    final nodesList = <CTag>[];

    var i = 0;
    for (final railNode in nodes.values) {
      indexTracker[railNode] = i;
      final nodeTag = CTag();
      nodeTag.putCompound('Location', railNode.getLocation().write(dimensions));
      nodeTag.putVec3('Normal', railNode.getNormal());
      nodesList.add(nodeTag);
      i++;
    }

    connectionsByNode.forEach((node1, map) {
      final index1 = indexTracker[node1];
      if (index1 == null) return;
      final nodeTag = nodesList[index1];
      final connectionsList = <CTag>[];
      map.forEach((node2, edge) {
        final connectionTag = CTag();
        final index2 = indexTracker[node2];
        if (index2 == null) return;
        connectionTag.putInt('To', index2);
        connectionTag.putCompound('EdgeData', edge.write(dimensions));
        connectionsList.add(connectionTag);
      });
      nodeTag.putCompoundList('Connections', connectionsList);
    });

    tag.putCompoundList('Nodes', nodesList);
    tag.putCompound('Points', edgePoints.write(dimensions));
    return tag;
  }

  static TrackGraph read(CTag tag, DimensionPalette dimensions) {
    final graph = TrackGraph(tag.getUuid('Id') ?? (throw const FormatException('TrackGraph without Id')));
    graph.color = tag.getInt('Color');
    graph.edgePoints.read(tag.getCompound('Points'), dimensions);

    final indexTracker = <int, TrackNode>{};
    final nodesList = tag.getCompoundList('Nodes');

    var i = 0;
    for (final nodeTag in nodesList) {
      final location = TrackNodeLocation.read(nodeTag.getCompound('Location'), dimensions);
      final normal = nodeTag.getVec3('Normal');
      graph.loadNode(location, nextNodeId(), normal);
      indexTracker[i] = graph.locateNode(location)!;
      i++;
    }

    i = 0;
    for (final nodeTag in nodesList) {
      final node1 = indexTracker[i]!;
      i++;

      if (!nodeTag.contains('Connections')) continue;
      for (final c in nodeTag.getCompoundList('Connections')) {
        final node2 = indexTracker[c.getInt('To')]!;
        final edge = TrackEdge.read(node1, node2, c.getCompound('EdgeData'), graph, dimensions);
        graph.putConnection(node1, node2, edge);
      }
    }

    return graph;
  }
}
