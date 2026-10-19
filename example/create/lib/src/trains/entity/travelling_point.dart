// `TravellingPoint` (pure): a point travelling along the edges of a track graph. Wheels of
// bogeys, navigation scouts and relocation probes are travelling points. The algorithm follows
// the Java class step by step (edge steps, signal / edge point listeners, node selection,
// reversed travel, portals).
import 'dart:collection';

import '../../common/data.dart';
import '../../common/direction.dart' show mthEqual;
import '../../common/vec_helper.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_graph_location.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../manager/create.dart';
import '../signal/track_edge_point.dart';
import '../util/ctag.dart';

/// `TravellingPoint.SteerDirection`.
enum SteerDirection {
  none(0),
  left(-1),
  right(1);

  const SteerDirection(this.targetDot);

  final double targetDot;
}

/// `ITrackSelector`: picks the entry to continue on. The pair holds `forward` and the valid
/// targets.
typedef ITrackSelector =
    MapEntry<TrackNode, TrackEdge> Function(TrackGraph graph, Pair<bool, List<MapEntry<TrackNode, TrackEdge>>> pair);

/// `IEdgePointListener`: called with the distance and the edge point with the nodes it is
/// crossed through; returning `true` stops the point at the edge point.
typedef IEdgePointListener = bool Function(double distance, Pair<TrackEdgePoint, Couple<TrackNode>> pair);

/// `ITurnListener`.
typedef ITurnListener = void Function(double distance, TrackEdge edge);

/// `IPortalListener`: `true` blocks the portal crossing.
typedef IPortalListener = bool Function(Couple<TrackNodeLocation> locations);

class TravellingPoint {
  TrackNode? node1;
  TrackNode? node2;
  TrackEdge? edge;
  double position = 0;
  bool blocked = false;
  bool upsideDown = false;

  TravellingPoint();

  TravellingPoint.at(this.node1, this.node2, this.edge, this.position, this.upsideDown);

  IEdgePointListener ignoreEdgePoints() => (d, c) => false;

  ITurnListener ignoreTurns() => (d, c) {};

  IPortalListener ignorePortals() => (_) => false;

  ITrackSelector random() => (graph, pair) {
    final targets = pair.getSecond();
    return targets[Create.RANDOM.nextInt(targets.length)];
  };

  ITrackSelector follow(TravellingPoint other, [void Function(bool success)? success]) {
    return (graph, pair) {
      final validTargets = pair.getSecond();
      final forward = pair.getFirst();
      final target = forward ? other.node1 : other.node2;
      final secondary = forward ? other.node2 : other.node1;

      for (final entry in validTargets) {
        if (identical(entry.key, target) || identical(entry.key, secondary)) {
          success?.call(true);
          return entry;
        }
      }

      final frontiers = <List<MapEntry<TrackNode, TrackEdge>>>[];
      final visiteds = <Set<TrackEdge>>[];

      for (final validTarget in validTargets) {
        frontiers.add([validTarget]);
        visiteds.add(HashSet<TrackEdge>.identity()..add(validTarget.value));
      }

      for (var i = 0; i < 20; i++) {
        for (var j = 0; j < validTargets.length; j++) {
          final entry = validTargets[j];
          final frontier = frontiers[j];
          if (frontier.isEmpty) continue;

          final currentEntry = frontier.removeAt(0);
          for (final nextEntry in graph.getConnectionsFrom(currentEntry.key).entries) {
            final nextEdge = nextEntry.value;
            if (!visiteds[j].add(nextEdge)) continue;
            if (!currentEntry.value.canTravelTo(nextEdge)) continue;

            final nextNode = nextEntry.key;
            if (identical(nextNode, target)) {
              success?.call(true);
              return entry;
            }

            frontier.add(nextEntry);
          }
        }
      }

      success?.call(false);
      return validTargets[0];
    };
  }

  ITrackSelector steer(SteerDirection direction, Vec3 upNormal) {
    return (graph, pair) {
      final validTargets = pair.getSecond();
      var closest = double.maxFinite;
      MapEntry<TrackNode, TrackEdge>? best;

      for (final entry in validTargets) {
        final trajectory = edge!.getDirection(false);
        final entryTrajectory = entry.value.getDirection(true);
        final normal = trajectory.cross(upNormal);
        final dot = normal.dot(entryTrajectory);
        final diff = (direction.targetDot - dot).abs();
        if (diff > closest) continue;

        closest = diff;
        best = entry;
      }

      // Create.LOGGER.warn("Couldn't find steer target, choosing first")
      return best ?? validTargets[0];
    };
  }

  double travel(
    TrackGraph graph,
    double distance,
    ITrackSelector trackSelector, [
    IEdgePointListener? signalListener,
    ITurnListener? turnListener,
    IPortalListener? portalListener,
  ]) {
    final edgePointListener = signalListener ?? ignoreEdgePoints();
    final turnCallback = turnListener ?? ignoreTurns();
    final portalCallback = portalListener ?? ignorePortals();

    blocked = false;
    if (edge == null) return 0;
    var edgeLength = edge!.getLength();
    if (mthEqual(distance, 0)) return 0;

    var prevPos = position;
    var traveled = distance;
    final currentT = edgeLength == 0 ? 0.0 : position / edgeLength;
    final incrementT = edge!.incrementT(currentT, distance);
    position = incrementT * edgeLength;

    // FIXME (Java): using incrementT like this becomes inaccurate at medium-long distances;
    // a workaround lives in TrackEdge.incrementT.

    final validTargets = <MapEntry<TrackNode, TrackEdge>>[];

    final forward = distance > 0;
    var collectedDistance = forward ? -prevPos : -edgeLength + prevPos;

    var blockedLocation = edgeTraversedFrom(graph, forward, edgePointListener, turnCallback, prevPos, collectedDistance);
    if (blockedLocation != null) {
      position = blockedLocation;
      traveled = position - prevPos;
      return traveled;
    }

    if (forward) {
      // Moving forward
      while (position > edgeLength) {
        validTargets.clear();

        for (final entry in graph.getConnectionsFrom(node2!).entries) {
          final newNode = entry.key;
          if (identical(newNode, node1)) continue;

          final newEdge = entry.value;
          if (!edge!.canTravelTo(newEdge)) continue;

          validTargets.add(entry);
        }

        if (validTargets.isEmpty) {
          traveled -= position - edgeLength;
          position = edgeLength;
          blocked = true;
          break;
        }

        final entry = validTargets.length == 1
            ? validTargets[0]
            : trackSelector(graph, Pair.of(true, validTargets));

        if (entry.value.getLength() == 0 &&
            portalCallback(Couple.create(node2!.getLocation(), entry.key.getLocation()))) {
          traveled -= position - edgeLength;
          position = edgeLength;
          blocked = true;
          break;
        }

        node1 = node2;
        node2 = entry.key;
        edge = entry.value;
        position -= edgeLength;

        collectedDistance += edgeLength;
        if (edge!.isTurn()) turnCallback(collectedDistance, edge!);

        blockedLocation = edgeTraversedFrom(graph, forward, edgePointListener, turnCallback, 0, collectedDistance);

        if (blockedLocation != null) {
          traveled -= position;
          position = blockedLocation;
          traveled += position;
          break;
        }

        prevPos = 0;
        edgeLength = edge!.getLength();
      }
    } else {
      // Moving backwards
      while (position < 0) {
        validTargets.clear();

        for (final entry in graph.getConnectionsFrom(node1!).entries) {
          final newNode = entry.key;
          if (identical(newNode, node2)) continue;
          if (!graph.getConnectionsFrom(newNode)[node1]!.canTravelTo(edge!)) continue;

          validTargets.add(entry);
        }

        if (validTargets.isEmpty) {
          traveled -= position;
          position = 0;
          blocked = true;
          break;
        }

        final entry = validTargets.length == 1
            ? validTargets[0]
            : trackSelector(graph, Pair.of(false, validTargets));

        if (entry.value.getLength() == 0 &&
            portalCallback(Couple.create(entry.key.getLocation(), node1!.getLocation()))) {
          traveled -= position;
          position = 0;
          blocked = true;
          break;
        }

        node2 = node1;
        node1 = entry.key;
        edge = graph.getConnectionsFrom(node1!)[node2];
        collectedDistance += edgeLength;
        edgeLength = edge!.getLength();
        position += edgeLength;

        blockedLocation = edgeTraversedFrom(graph, forward, edgePointListener, turnCallback, edgeLength, collectedDistance);

        if (blockedLocation != null) {
          traveled -= position;
          position = blockedLocation;
          traveled += position;
          break;
        }
      }
    }

    return traveled;
  }

  /// `edgeTraversedFrom`: calls the listeners for what lies on the traversed part of the current
  /// edge; returns the location of the edge point that stopped the travel, or `null`.
  double? edgeTraversedFrom(
    TrackGraph graph,
    bool forward,
    IEdgePointListener edgePointListener,
    ITurnListener turnListener,
    double prevPos,
    double totalDistance,
  ) {
    if (edge!.isTurn()) turnListener(totalDistance < 0 ? 0 : totalDistance, edge!);

    final from = forward ? prevPos : position;
    final to = forward ? position : prevPos;

    final edgeData = edge!.getEdgeData();
    final edgePoints = edgeData.getPoints();

    final length = edge!.getLength();
    for (var i = 0; i < edgePoints.length; i++) {
      final index = forward ? i : edgePoints.length - i - 1;
      final nextBoundary = edgePoints[index];
      final locationOn = nextBoundary.getLocationOn(edge!);
      final distance = forward ? locationOn : length - locationOn;
      if (forward ? (locationOn < from || locationOn >= to) : (locationOn <= from || locationOn > to)) continue;
      final nodes = Couple.create<TrackNode>(node1!, node2!);
      if (edgePointListener(totalDistance + distance, Pair.of(nextBoundary, forward ? nodes : nodes.swap()))) {
        return locationOn;
      }
    }

    return null;
  }

  void reverse(TrackGraph graph) {
    final n = node1;
    node1 = node2;
    node2 = n;
    position = edge!.getLength() - position;
    edge = graph.getConnectionsFrom(node1!)[node2];
  }

  /// `getPosition(trackGraph)` / `getPosition(trackGraph, flipUpsideDown)`.
  Vec3 getPosition(TrackGraph? trackGraph, [bool flipUpsideDown = false]) =>
      getPositionWithOffset(trackGraph, 0, flipUpsideDown);

  Vec3 getPositionWithOffset(TrackGraph? trackGraph, double offset, bool flipUpsideDown) {
    final t = (position + offset) / edge!.getLength();
    return edge!.getPosition(trackGraph, t) + edge!.getNormal(trackGraph, t) * (upsideDown ^ flipUpsideDown ? -1 : 1);
  }

  void migrateTo(List<TrackGraphLocation> locations) {
    final location = locations.removeAt(0);
    final graph = location.graph;
    node1 = graph.locateNode(location.edge.getFirst());
    node2 = graph.locateNode(location.edge.getSecond());
    position = location.position;
    edge = graph.getConnectionsFrom(node1!)[node2];
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    final a = node1;
    final b = node2;
    if (a == null || b == null) return tag;
    tag.putCompoundList('Nodes', [a.getLocation().write(dimensions), b.getLocation().write(dimensions)]);
    tag.putDouble('Position', position);
    tag.putBoolean('UpsideDown', upsideDown);
    return tag;
  }

  static TravellingPoint read(CTag tag, TrackGraph? graph, DimensionPalette dimensions) {
    if (graph == null) return TravellingPoint.at(null, null, null, 0, false);

    TrackNode? first;
    TrackNode? second;
    if (tag.contains('Nodes')) {
      final nodes = tag.getCompoundList('Nodes');
      if (nodes.length >= 2) {
        first = graph.locateNode(TrackNodeLocation.read(nodes[0], dimensions));
        second = graph.locateNode(TrackNodeLocation.read(nodes[1], dimensions));
      }
    }

    if (first == null || second == null) return TravellingPoint.at(null, null, null, 0, false);

    final position = tag.getDouble('Position');
    return TravellingPoint.at(first, second, graph.getConnectionsFrom(first)[second], position, tag.getBoolean('UpsideDown'));
  }
}
