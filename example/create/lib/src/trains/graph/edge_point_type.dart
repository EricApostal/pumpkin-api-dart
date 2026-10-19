// ignore_for_file: constant_identifier_names, non_constant_identifier_names
// `EdgePointType` (pure): the kinds of edge points and their factories.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/byte_buf.dart';
import '../manager/create.dart';
import '../observer/track_observer.dart';
import '../signal/signal_boundary.dart';
import '../signal/track_edge_point.dart';
import '../station/global_station.dart';
import 'dimension_palette.dart';

class EdgePointType<T extends TrackEdgePoint> {
  final String _id;
  final T Function() _factory;

  static final EdgePointType<SignalBoundary> SIGNAL = EdgePointType(Create.asResource('signal'), SignalBoundary.new);
  static final EdgePointType<GlobalStation> STATION = EdgePointType(Create.asResource('station'), GlobalStation.new);
  static final EdgePointType<TrackObserver> OBSERVER = EdgePointType(Create.asResource('observer'), TrackObserver.new);

  /// All types by identifier (`EdgePointType.TYPES`), the three of Create first.
  static final Map<String, EdgePointType<TrackEdgePoint>> TYPES = {
    for (final t in <EdgePointType<TrackEdgePoint>>[SIGNAL, STATION, OBSERVER]) t.getId(): t,
  };

  static EdgePointType<T> register<T extends TrackEdgePoint>(String id, T Function() factory) {
    final type = EdgePointType<T>(id, factory);
    TYPES[id] = type;
    return type;
  }

  EdgePointType(this._id, this._factory);

  T create() {
    final t = _factory();
    t.setType(this);
    return t;
  }

  String getId() => _id;

  /// `read(FriendlyByteBuf, dimensions)`: the identifier, then the point.
  static TrackEdgePoint read(PacketReader buffer, DimensionPalette dimensions) {
    final type = buffer.readId();
    final edgePointType = TYPES[type] ?? (throw PacketException('Unknown edge point type $type'));
    final point = edgePointType.create();
    point.readBuffer(buffer, dimensions);
    return point;
  }
}
