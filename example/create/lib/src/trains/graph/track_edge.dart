// `TrackEdge` (pure): a directed edge between two nodes, straight or a bezier turn.
import 'dart:math' as math;

import '../../common/bounds.dart';
import '../../common/direction.dart' show Axis, clampNum, toFloat;
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../track/bezier_connection.dart';
import '../track/track_material.dart';
import '../util/ctag.dart';
import 'dimension_palette.dart';
import 'edge_data.dart';
import 'track_graph.dart';
import 'track_node.dart';

class TrackEdge {
  TrackNode node1;
  TrackNode node2;
  BezierConnection? turn;
  late EdgeData edgeData;
  bool interDimensional;
  TrackMaterial trackMaterial;

  TrackEdge(this.node1, this.node2, this.turn, this.trackMaterial)
    : interDimensional = node1.location.dimension != node2.location.dimension {
    edgeData = EdgeData(this);
  }

  TrackMaterial getTrackMaterial() => trackMaterial;

  bool isTurn() => turn != null;

  bool isInterDimensional() => interDimensional;

  EdgeData getEdgeData() => edgeData;

  BezierConnection? getTurn() => turn;

  Vec3 getDirection(bool fromFirst) =>
      (getPosition(null, fromFirst ? 0.25 : 1) - getPosition(null, fromFirst ? 0 : 0.75)).normalized;

  Vec3 getDirectionAt(double t) {
    final length = getLength();
    final step = .5 / length;
    t /= length;
    final ahead = getPosition(null, math.min(1, t + step));
    final behind = getPosition(null, math.max(0, t - step));
    return (ahead - behind).normalized;
  }

  bool canTravelTo(TrackEdge other) {
    if (isInterDimensional() || other.isInterDimensional()) return true;
    final newDirection = other.getDirection(true);
    return getDirection(false).dot(newDirection) > 7 / 8.0;
  }

  double getLength() => isInterDimensional()
      ? 0
      : isTurn()
      ? turn!.getLength()
      : node1.location.getLocation().distanceTo(node2.location.getLocation());

  double incrementT(double currentT, double distance) {
    final tooFar = distance.abs() > 5;
    final length = getLength();
    distance = distance / (length == 0 ? 1 : length);
    return !tooFar && isTurn() ? turn!.incrementT(currentT, distance) : currentT + distance;
  }

  Vec3 getPosition(TrackGraph? trackGraph, double t) {
    if (isTurn()) return turn!.getPosition(clampNum(t, 0.0, 1.0));
    if (trackGraph != null && (node1.location.yOffsetPixels != 0 || node2.location.yOffsetPixels != 0)) {
      final positionSmoothed = getPositionSmoothed(trackGraph, t);
      if (positionSmoothed != null) return positionSmoothed;
    }
    return VecHelper.lerp(toFloat(t), node1.location.getLocation(), node2.location.getLocation());
  }

  Vec3 getNormal(TrackGraph? trackGraph, double t) {
    if (isTurn()) return turn!.getNormal(clampNum(t, 0.0, 1.0));
    if (trackGraph != null && (node1.location.yOffsetPixels != 0 || node2.location.yOffsetPixels != 0)) {
      final normalSmoothed = getNormalSmoothed(trackGraph, t);
      if (normalSmoothed != null) return normalSmoothed;
    }
    return node1.getNormal();
  }

  Vec3? getPositionSmoothed(TrackGraph trackGraph, double t) {
    Vec3? node1Location;
    Vec3? node2Location;
    for (final trackEdge in trackGraph.getConnectionsFrom(node1).values) {
      if (trackEdge.isTurn()) node1Location = trackEdge.getPosition(trackGraph, 0);
    }
    for (final trackEdge in trackGraph.getConnectionsFrom(node2).values) {
      if (trackEdge.isTurn()) node2Location = trackEdge.getPosition(trackGraph, 0);
    }
    if (node1Location == null || node2Location == null) return null;
    return VecHelper.lerp(toFloat(t), node1Location, node2Location);
  }

  Vec3? getNormalSmoothed(TrackGraph trackGraph, double t) {
    Vec3? node1Normal;
    Vec3? node2Normal;
    for (final trackEdge in trackGraph.getConnectionsFrom(node1).values) {
      if (trackEdge.isTurn()) node1Normal = trackEdge.getNormal(trackGraph, 0);
    }
    for (final trackEdge in trackGraph.getConnectionsFrom(node2).values) {
      if (trackEdge.isTurn()) node2Normal = trackEdge.getNormal(trackGraph, 0);
    }
    if (node1Normal == null || node2Normal == null) return null;
    return VecHelper.lerp(0.5, node1Normal, node2Normal);
  }

  /// `getIntersection(node1, node2, other, other1, other2)`: pairs `[s, t]` of the distances on this
  /// edge and on [other].
  List<List<double>> getIntersection(TrackNode node1, TrackNode node2, TrackEdge other, TrackNode other1, TrackNode other2) {
    final v1 = node1.location.getLocation();
    final v2 = node2.location.getLocation();
    final w1 = other1.location.getLocation();
    final w2 = other2.location.getLocation();

    if (isInterDimensional() || other.isInterDimensional()) return const [];
    if (v1.$2 != v2.$2 || v1.$2 != w1.$2 || v1.$2 != w2.$2) return const [];

    if (!isTurn()) {
      if (!other.isTurn()) {
        final hit = VecHelper.intersectRanged(v1, w1, v2, w2, Axis.y);
        return hit == null ? const [] : [hit];
      }
      return [
        for (final a in other.getIntersection(other1, other2, this, node1, node2)) [a[1], a[0]],
      ];
    }

    final bb = turn!.getBounds();

    if (!other.isTurn()) {
      if (!bb.intersects(Aabb.between(w1, w2))) return const [];

      var seg1 = v1;
      Vec3 seg2;
      var t = 0.0;

      final intersections = <List<double>>[];
      for (var i = 0; i < turn!.getSegmentCount(); i++) {
        final tOffset = t;
        t += .5;
        seg2 = getPosition(null, t / getLength());
        final intersection = VecHelper.intersectRanged(seg1, w1, seg2, w2, Axis.y);
        seg1 = seg2;
        if (intersection == null) continue;
        intersection[0] += tOffset;
        intersections.add(intersection);
      }

      return intersections;
    }

    if (!bb.intersects(other.turn!.getBounds())) return const [];

    var seg1 = v1;
    Vec3 seg2;
    var t = 0.0;

    final intersections = <List<double>>[];
    for (var i = 0; i < turn!.getSegmentCount(); i++) {
      final tOffset = t;
      t += .5;
      seg2 = getPosition(null, t / getLength());

      var otherSeg1 = w1;
      Vec3 otherSeg2;
      var u = 0.0;

      for (var j = 0; j < other.turn!.getSegmentCount(); j++) {
        final uOffset = u;
        u += .5;
        otherSeg2 = other.getPosition(null, u / other.getLength());

        final intersection = VecHelper.intersectRanged(seg1, otherSeg1, seg2, otherSeg2, Axis.y);
        otherSeg1 = otherSeg2;

        if (intersection == null) continue;

        intersection[0] += tOffset;
        intersection[1] += uOffset;
        intersections.add(intersection);
      }

      seg1 = seg2;
    }

    return intersections;
  }

  CTag write(DimensionPalette? dimensions) {
    final baseCompound = isTurn() ? turn!.write(posZero) : CTag();
    baseCompound.putCompound('Signals', edgeData.write(dimensions));
    baseCompound.putString('Material', getTrackMaterial().id);
    return baseCompound;
  }

  static TrackEdge read(TrackNode node1, TrackNode node2, CTag tag, TrackGraph graph, DimensionPalette? dimensions) {
    final trackEdge = TrackEdge(
      node1,
      node2,
      tag.contains('Positions') ? BezierConnection.fromTag(tag, posZero) : null,
      TrackMaterial.deserialize(tag.getString('Material')),
    );
    trackEdge.edgeData = EdgeData.read(tag.getCompound('Signals'), trackEdge, graph, dimensions);
    return trackEdge;
  }
}
