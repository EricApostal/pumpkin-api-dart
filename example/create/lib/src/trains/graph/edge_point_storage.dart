// `EdgePointStorage` (pure): the edge points of a graph by type and id.
import '../manager/create.dart';
import '../signal/track_edge_point.dart';
import '../util/ctag.dart';
import 'dimension_palette.dart';
import 'edge_point_type.dart';
import 'track_graph.dart';

class EdgePointStorage {
  final Map<EdgePointType<TrackEdgePoint>, Map<String, TrackEdgePoint>> pointsByType = Map.identity();

  void put<T extends TrackEdgePoint>(EdgePointType<T> type, TrackEdgePoint point) {
    getMap(type)[point.getId()] = point;
  }

  T? get<T extends TrackEdgePoint>(EdgePointType<T> type, String id) => getMap(type)[id] as T?;

  T? remove<T extends TrackEdgePoint>(EdgePointType<T> type, String id) => getMap(type).remove(id) as T?;

  List<T> values<T extends TrackEdgePoint>(EdgePointType<T> type) => [for (final e in getMap(type).values) e as T];

  Map<String, TrackEdgePoint> getMap(EdgePointType<TrackEdgePoint> type) =>
      pointsByType.putIfAbsent(type, () => <String, TrackEdgePoint>{});

  void tick(TrackGraph graph, bool preTrains) {
    for (final map in pointsByType.values.toList()) {
      for (final point in map.values.toList()) {
        point.tick(graph, preTrains);
      }
    }
  }

  void transferAll(TrackGraph target, EdgePointStorage other) {
    pointsByType.forEach((type, map) {
      other.getMap(type).addAll(map);
      for (final ep in map.values) {
        Create.RAILWAYS.sync.pointAdded(target, ep);
      }
    });
    pointsByType.clear();
  }

  CTag write(DimensionPalette dimensions) {
    final nbt = CTag();
    pointsByType.forEach((type, map) {
      final list = <CTag>[];
      for (final edgePoint in map.values) {
        final tag = CTag();
        edgePoint.write(tag, dimensions);
        list.add(tag);
      }
      nbt.putCompoundList(type.getId(), list);
    });
    return nbt;
  }

  void read(CTag nbt, DimensionPalette dimensions) {
    for (final type in EdgePointType.TYPES.values) {
      final list = nbt.getCompoundList(type.getId());
      final map = getMap(type);
      for (final tag in list) {
        final edgePoint = type.create();
        edgePoint.read(tag, false, dimensions);
        map[edgePoint.getId()] = edgePoint;
      }
    }
  }
}
