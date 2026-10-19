// `EdgeData` (pure): the signal groups, edge points and intersections of one edge.
import '../../common/data.dart';
import '../../common/direction.dart' show mthEqual;
import '../manager/create.dart';
import '../signal/signal_boundary.dart';
import '../signal/track_edge_point.dart';
import '../util/ctag.dart';
import 'dimension_palette.dart';
import 'edge_point_type.dart';
import 'track_edge.dart';
import 'track_edge_intersection.dart';
import 'track_graph.dart';
import 'track_node.dart';

class EdgeData {
  /// `EdgeData.passiveGroup`: the nil uuid.
  // ignore: constant_identifier_names
  static const String passiveGroup = '00000000-0000-0000-0000-000000000000';

  String? _singleSignalGroup;
  List<TrackEdgePoint> points = [];
  List<TrackEdgeIntersection> intersections = [];
  final TrackEdge edge;

  EdgeData(this.edge) : _singleSignalGroup = passiveGroup;

  bool hasSignalBoundaries() => _singleSignalGroup == null;

  String? getSingleSignalGroup() => _singleSignalGroup;

  /// `setSingleSignalGroup(graph, group)`.
  void setSingleSignalGroup(TrackGraph? graph, String? singleSignalGroup) {
    if (graph != null && singleSignalGroup != _singleSignalGroup) refreshIntersectingSignalGroups(graph);
    _singleSignalGroup = singleSignalGroup;
  }

  void refreshIntersectingSignalGroups(TrackGraph graph) {
    final groups = Create.RAILWAYS.signalEdgeGroups;
    for (final intersection in intersections) {
      if (intersection.groupId == null) continue;
      final group = groups[intersection.groupId];
      group?.removeIntersection(intersection.id);
    }
    if (hasIntersections()) graph.deferIntersectionUpdate(edge);
  }

  bool hasPoints() => points.isNotEmpty;

  bool hasIntersections() => intersections.isNotEmpty;

  List<TrackEdgeIntersection> getIntersections() => intersections;

  void addIntersection(
    TrackGraph graph,
    String id,
    double position,
    TrackNode target1,
    TrackNode target2,
    double targetPosition,
  ) {
    final loc1 = target1.getLocation();
    final loc2 = target2.getLocation();

    for (final existing in intersections) {
      if (existing.isNear(position) && existing.targets(loc1, loc2)) return;
    }

    final intersection = TrackEdgeIntersection();
    intersection.id = id;
    intersection.location = position;
    intersection.target = Couple.create(loc1, loc2);
    intersection.targetLocation = targetPosition;
    intersections.add(intersection);
    graph.deferIntersectionUpdate(edge);
  }

  void removeIntersection(TrackGraph graph, String id) {
    refreshIntersectingSignalGroups(graph);
    intersections.removeWhere((existing) => existing.id == id);
  }

  String? getGroupAtPosition(TrackGraph graph, double position) {
    if (!hasSignalBoundaries()) return getEffectiveEdgeGroupId(graph);
    final firstSignal = next(EdgePointType.SIGNAL, 0);
    if (firstSignal == null) return null;
    var currentGroup = firstSignal.getGroup(edge.node1);

    for (final trackEdgePoint in getPoints()) {
      if (trackEdgePoint is! SignalBoundary) continue;
      if (trackEdgePoint.getLocationOn(edge) >= position) return currentGroup;
      currentGroup = trackEdgePoint.getGroup(edge.node2);
    }

    return currentGroup;
  }

  List<TrackEdgePoint> getPoints() => points;

  String? getEffectiveEdgeGroupId(TrackGraph graph) =>
      _singleSignalGroup == null ? null : (_singleSignalGroup == passiveGroup ? graph.id : _singleSignalGroup);

  void removePoint(TrackGraph graph, TrackEdgePoint point) {
    points.remove(point);
    if (point.getType() == EdgePointType.SIGNAL) {
      final noSignalsRemaining = next(point.getType(), 0) == null;
      setSingleSignalGroup(graph, noSignalsRemaining ? passiveGroup : null);
    }
  }

  void addPoint(TrackGraph graph, TrackEdgePoint point) {
    if (point.getType() == EdgePointType.SIGNAL) setSingleSignalGroup(graph, null);
    final locationOn = point.getLocationOn(edge);
    var i = 0;
    for (; i < points.length; i++) {
      if (points[i].getLocationOn(edge) > locationOn) break;
    }
    points.insert(i, point);
  }

  /// `next(type, minPosition)`: the first point of [type] after [minPosition].
  T? next<T extends TrackEdgePoint>(EdgePointType<T> type, double minPosition) {
    for (final point in points) {
      if (point.getType() == type && point.getLocationOn(edge) > minPosition) return point as T;
    }
    return null;
  }

  /// `next(minPosition)`: the first point of any type.
  TrackEdgePoint? nextAny(double minPosition) {
    for (final point in points) {
      if (point.getLocationOn(edge) > minPosition) return point;
    }
    return null;
  }

  T? get<T extends TrackEdgePoint>(EdgePointType<T> type, double exactPosition) {
    final next = this.next(type, exactPosition - .5);
    if (next != null && mthEqual(next.getLocationOn(edge), exactPosition)) return next;
    return null;
  }

  CTag write(DimensionPalette? dimensions) {
    final nbt = CTag();
    if (_singleSignalGroup == passiveGroup) {
      nbt.putMarker('PassiveGroup');
    } else if (_singleSignalGroup != null) {
      nbt.putUuid('SignalGroup', _singleSignalGroup!);
    }

    if (hasPoints()) {
      nbt.putCompoundList('Points', [
        for (final point in points)
          CTag()
            ..putUuid('Id', point.id)
            ..putString('Type', point.getType().getId()),
      ]);
    }
    if (hasIntersections()) {
      nbt.putCompoundList('Intersections', [for (final tei in intersections) tei.write(dimensions)]);
    }
    return nbt;
  }

  static EdgeData read(CTag nbt, TrackEdge edge, TrackGraph graph, DimensionPalette? dimensions) {
    final data = EdgeData(edge);
    if (nbt.contains('SignalGroup')) {
      data._singleSignalGroup = nbt.getUuid('SignalGroup') ?? (throw const FormatException('bad SignalGroup'));
    } else if (!nbt.contains('PassiveGroup')) {
      data._singleSignalGroup = null;
    }

    if (nbt.contains('Points')) {
      for (final tag in nbt.getCompoundList('Points')) {
        final location = tag.getString('Type');
        final type = EdgePointType.TYPES[location];
        if (type == null || !tag.contains('Id')) continue;
        final id = tag.getUuid('Id') ?? (throw const FormatException('bad edge point Id'));
        final point = graph.getPoint(type, id);
        if (point != null) data.points.add(point);
      }
    }
    if (nbt.contains('Intersections')) {
      data.intersections = [for (final c in nbt.getCompoundList('Intersections')) TrackEdgeIntersection.read(c, dimensions)];
    }
    return data;
  }
}
