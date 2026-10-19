// `CarriageSyncData` and `CarriageSyncDataSerializer` (pure): what the server tells the clients
// about where the wheels of a carriage are (the `create:carriage_data` entity data serializer).
// The byte layout is that of `CarriageSyncData.write(FriendlyByteBuf)`:
//
//   bool leadingCarriage
//   bool hasFallback
//   if hasFallback:  vec3 positionAnchor, vec3 rotationAnchors.first, vec3 rotationAnchors.second
//   else:            up to 4 x ( bool endOfList,  [ int node1NetId, int node2NetId, float position ] ),
//                    stopping after the first entry with endOfList = true;  float distanceToDestination
//
// (a vec3 is three doubles.) The client interpolation half of the Java class (`apply`, `approach`,
// `getDistanceTo`) is included; it runs on the real client, the server only fills the data with
// [update].
import 'dart:collection';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/data.dart';
import '../../common/direction.dart' show mthEqual, toFloat;
import '../../common/vec_helper.dart';
import '../../core/byte_buf.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import 'carriage.dart';
import 'carriage_contraption_entity.dart';
import 'java_priority_queue.dart';
import 'travelling_point.dart';

class CarriageSyncData {
  List<Pair<Couple<int>, double>?> wheelLocations = List<Pair<Couple<int>, double>?>.filled(4, null);
  Pair<Vec3, Couple<Vec3>>? fallbackLocations;
  double distanceToDestination = 0;
  bool leadingCarriage = false;

  // For Client interpolation
  Pair<Vec3, Couple<Vec3>>? _fallbackPointSnapshot;
  final List<TravellingPoint> _pointsToApproach = List<TravellingPoint>.generate(4, (_) => TravellingPoint());
  final List<double> _pointDistanceSnapshot = List<double>.filled(4, 0);
  double _destinationDistanceSnapshot = 0;
  int _ticksSince = 0;

  CarriageSyncData();

  /// `new CarriageSyncData(FriendlyByteBuf)`.
  CarriageSyncData.fromBuffer(PacketReader buf) {
    read(buf);
  }

  CarriageSyncData copy() {
    final data = CarriageSyncData();
    for (var i = 0; i < 4; i++) {
      data.wheelLocations[i] = wheelLocations[i];
    }
    if (fallbackLocations != null) {
      final f = fallbackLocations!;
      data.fallbackLocations = Pair.of(f.getFirst(), f.getSecond().copy());
    }
    data.distanceToDestination = distanceToDestination;
    data.leadingCarriage = leadingCarriage;
    return data;
  }

  void write(PacketWriter buffer) {
    buffer.writeBool(leadingCarriage);
    buffer.writeBool(fallbackLocations != null);

    if (fallbackLocations != null) {
      final contraptionAnchor = fallbackLocations!.getFirst();
      final rotationAnchors = fallbackLocations!.getSecond();
      buffer.writeVec3(contraptionAnchor);
      buffer.writeVec3(rotationAnchors.getFirst());
      buffer.writeVec3(rotationAnchors.getSecond());
      return;
    }

    for (final pair in wheelLocations) {
      buffer.writeBool(pair == null);
      if (pair == null) break;
      pair.getFirst().forEach(buffer.writeInt);
      buffer.writeFloat(pair.getSecond());
    }
    buffer.writeFloat(distanceToDestination);
  }

  void read(PacketReader buffer) {
    leadingCarriage = buffer.readBool();
    final fallback = buffer.readBool();
    _ticksSince = 0;

    if (fallback) {
      fallbackLocations = Pair.of(buffer.readVec3(), Couple.create(buffer.readVec3(), buffer.readVec3()));
      return;
    }

    fallbackLocations = null;
    for (var i = 0; i < 4; i++) {
      if (buffer.readBool()) break;
      final a = buffer.readInt();
      final b = buffer.readInt();
      wheelLocations[i] = Pair.of(Couple.create(a, b), buffer.readFloat());
    }
    distanceToDestination = buffer.readFloat();
  }

  /// The bytes of [write].
  Uint8List toBytes() {
    final w = PacketWriter();
    write(w);
    return w.toBytes();
  }

  /// `update(entity, carriage)`: server side, fills the data from the wheel points.
  void update(CarriageContraptionEntity entity, Carriage carriage) {
    final dce = carriage.getDimensional(entity.dimension);

    final graph = carriage.train!.graph;
    if (graph == null) {
      _updateFallbackLocations(dce);
      return;
    }

    fallbackLocations = null;
    leadingCarriage =
        entity.carriageIndex == (carriage.train!.speed >= 0 ? 0 : carriage.train!.carriages.length - 1);

    for (final first in Iterate.trueAndFalse) {
      if (!first && !carriage.isOnTwoBogeys()) break;

      final bogey = carriage.bogeys.get(first)!;
      for (final firstPoint in Iterate.trueAndFalse) {
        final point = bogey.points.get(firstPoint);
        final index = (first ? 0 : 2) + (firstPoint ? 0 : 1);
        final node1 = point.node1;
        final node2 = point.node2;

        if (node1 == null || node2 == null) {
          _updateFallbackLocations(dce);
          return;
        }

        wheelLocations[index] = Pair.of(Couple.create(node1.getNetId(), node2.getNetId()), toFloat(point.position));
      }
    }

    distanceToDestination = toFloat(carriage.train!.navigation.distanceToDestination);
    setDirty(true);
  }

  void _updateFallbackLocations(DimensionalCarriageEntity dce) {
    final anchor = dce.positionAnchor;
    final r1 = dce.rotationAnchors.getFirst();
    final r2 = dce.rotationAnchors.getSecond();
    // The wire needs all three anchors; a carriage that never had any keeps the old data.
    if (anchor != null && r1 != null && r2 != null) {
      fallbackLocations = Pair.of(anchor, Couple.create(r1, r2));
    }
    dce.pointsInitialised = true;
    setDirty(true);
  }

  void apply(CarriageContraptionEntity entity, Carriage carriage) {
    final dce = carriage.getDimensional(entity.dimension);

    _fallbackPointSnapshot = null;
    if (fallbackLocations != null) {
      final anchor = dce.positionAnchor;
      final r1 = dce.rotationAnchors.getFirst();
      final r2 = dce.rotationAnchors.getSecond();
      if (anchor != null && r1 != null && r2 != null) {
        _fallbackPointSnapshot = Pair.of(anchor, Couple.create(r1, r2));
      }
      dce.pointsInitialised = true;
      return;
    }

    final graph = carriage.train!.graph;
    if (graph == null) return;

    for (var i = 0; i < wheelLocations.length; i++) {
      final pair = wheelLocations[i];
      if (pair == null) break;

      final bogey = carriage.bogeys.get(i ~/ 2 == 0)!;
      final bogeyPoint = bogey.points.get(i % 2 == 0);
      final point = dce.pointsInitialised ? _pointsToApproach[i] : bogeyPoint;

      final n1 = graph.getNode(pair.getFirst().getFirst());
      final n2 = graph.getNode(pair.getFirst().getSecond());
      if (n1 == null || n2 == null) continue;
      final edge = graph.getConnectionsFrom(n1)[n2];
      if (edge == null) continue;

      point.node1 = n1;
      point.node2 = n2;
      point.edge = edge;
      point.position = pair.getSecond();

      if (dce.pointsInitialised) {
        double foundDistance = -1;
        var direction = false;
        for (final forward in Iterate.trueAndFalse) {
          final distanceTo = getDistanceTo(graph, bogeyPoint, point, foundDistance, forward);
          if (distanceTo > 0 && (foundDistance == -1 || distanceTo < foundDistance)) {
            foundDistance = distanceTo;
            direction = forward;
          }
        }

        if (foundDistance != -1) {
          _pointDistanceSnapshot[i] = (direction ? 1 : -1) * foundDistance;
        } else {
          // could not pathfind to server location
          bogeyPoint.node1 = point.node1;
          bogeyPoint.node2 = point.node2;
          bogeyPoint.edge = point.edge;
          bogeyPoint.position = point.position;
          _pointDistanceSnapshot[i] = 0;
        }
      }
    }

    if (!dce.pointsInitialised) {
      carriage.train!.navigation.distanceToDestination = distanceToDestination;
      dce.pointsInitialised = true;
      return;
    }

    if (!leadingCarriage) return;

    _destinationDistanceSnapshot = toFloat(distanceToDestination - carriage.train!.navigation.distanceToDestination);
  }

  /// `approach(entity, carriage, partialIn)`; [updateInterval] is `getType().updateInterval()` of
  /// the entity type and [serverSpeed] `ServerSpeedProvider.get()`.
  void approach(
    CarriageContraptionEntity entity,
    Carriage carriage,
    double partialIn,
    int updateInterval, [
    double serverSpeed = 1,
  ]) {
    final dce = carriage.getDimensional(entity.dimension);

    if (_ticksSince >= updateInterval * 2) partialIn /= _ticksSince - updateInterval * 2 + 1;
    partialIn *= serverSpeed;
    final partial = toFloat(partialIn);

    _ticksSince++;

    if (fallbackLocations != null && _fallbackPointSnapshot != null) {
      dce.positionAnchor = _approachVector(partial, dce.positionAnchor, fallbackLocations!.getFirst(), _fallbackPointSnapshot!.getFirst());
      dce.rotationAnchors.replaceWithContext(
        (current, first) => _approachVector(
          partial,
          current,
          fallbackLocations!.getSecond().get(first),
          _fallbackPointSnapshot!.getSecond().get(first),
        ),
      );
      return;
    }

    final graph = carriage.train!.graph;
    if (graph == null) return;

    carriage.train!.navigation.distanceToDestination += partial * _destinationDistanceSnapshot;

    for (final first in Iterate.trueAndFalse) {
      if (!first && !carriage.isOnTwoBogeys()) break;
      final bogey = carriage.bogeys.get(first)!;
      for (final firstPoint in Iterate.trueAndFalse) {
        final index = (first ? 0 : 2) + (firstPoint ? 0 : 1);
        final f = _pointDistanceSnapshot[index];
        if (mthEqual(f, 0)) continue;

        final point = bogey.points.get(firstPoint);
        var success = true;
        final toApproach = _pointsToApproach[index];

        final trackSelector = point.follow(toApproach, (b) => success = success && b);
        point.travel(graph, partial * f, trackSelector);

        // could not pathfind to server location
        if (!success) {
          point.node1 = toApproach.node1;
          point.node2 = toApproach.node2;
          point.edge = toApproach.edge;
          point.position = toApproach.position;
          _pointDistanceSnapshot[index] = 0;
        }
      }
    }
  }

  Vec3? _approachVector(double partial, Vec3? current, Vec3 target, Vec3? snapshot) {
    if (current == null || snapshot == null) return target;
    return current + (target - snapshot) * partial;
  }

  /// `getDistanceTo(graph, current, target, maxDistance, forward)`: the distance along the track
  /// from [current] to [target], or -1.
  double getDistanceTo(TrackGraph graph, TravellingPoint current, TravellingPoint target, double maxDistance, bool forward) {
    if (maxDistance == -1) maxDistance = 32;

    final visited = HashSet<TrackEdge>.identity();
    final frontier = JavaPriorityQueue<Pair<double, Pair<Couple<TrackNode>, TrackEdge>>>(
      (p1, p2) => p1.getFirst().compareTo(p2.getFirst()),
    );

    final initialNode1 = forward ? current.node1 : current.node2;
    final initialNode2 = forward ? current.node2 : current.node1;

    final connectionsFromInitial = graph.getConnectionsFrom(initialNode1);

    final initialEdge = connectionsFromInitial[initialNode2];
    if (initialEdge == null) return -1; // graph changed

    final targetNode1 = forward ? target.node1 : target.node2;
    final targetNode2 = forward ? target.node2 : target.node1;
    final targetEdge = graph.getConnectionsFrom(targetNode1)[targetNode2];

    final distanceToNode2 = forward ? initialEdge.getLength() - current.position : current.position;

    frontier.add(Pair.of(distanceToNode2, Pair.of(Couple.create(initialNode1!, initialNode2!), initialEdge)));

    while (frontier.isNotEmpty) {
      final poll = frontier.poll()!;
      final distance = poll.getFirst();

      final currentEntry = poll.getSecond();
      final node2 = currentEntry.getFirst().getSecond();
      final edge = currentEntry.getSecond();

      if (identical(edge, targetEdge)) {
        return toFloat(distance - (forward ? edge.getLength() - target.position : target.position));
      }

      if (distance > maxDistance) continue;

      final validTargets = <MapEntry<TrackNode, TrackEdge>>[];
      final connectionsFrom = graph.getConnectionsFrom(node2);
      for (final entry in connectionsFrom.entries) {
        final newEdge = entry.value;
        final currentDirection = edge.getDirection(false);
        final newDirection = newEdge.getDirection(true);
        if (currentDirection.dot(newDirection) < toFloat(7 / 8.0)) continue;
        if (!visited.add(entry.value)) continue;
        validTargets.add(entry);
      }

      if (validTargets.isEmpty) continue;

      for (final entry in validTargets) {
        final newNode = entry.key;
        final newEdge = entry.value;
        frontier.add(Pair.of(newEdge.getLength() + distance, Pair.of(Couple.create(node2, newNode), newEdge)));
      }
    }

    return -1;
  }

  bool _isDirty = false;

  void setDirty(bool dirty) {
    _isDirty = dirty;
  }

  bool isDirty() => _isDirty;
}

/// `CarriageSyncDataSerializer`: the entity data serializer `create:carriage_data`.
abstract final class CarriageSyncDataSerializer {
  static const String id = 'create:carriage_data';

  /// `STREAM_CODEC` write: the bytes of the value.
  static Uint8List encode(CarriageSyncData data) => data.toBytes();

  /// `STREAM_CODEC` read.
  static CarriageSyncData decode(List<int> bytes) => CarriageSyncData.fromBuffer(PacketReader(bytes));

  /// `copy(data)`.
  static CarriageSyncData copy(CarriageSyncData data) => data.copy();
}
