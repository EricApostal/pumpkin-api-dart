// `TrackEdgePoint` (pure): something placed on an edge of the graph (signal, station, observer).
//
// Java -> Dart: `write(CompoundTag, registries, dimensions)` -> `write(CTag, dimensions)`;
// `read(CompoundTag, registries, migration, dimensions)` -> `read(CTag, migration, dimensions)`;
// the `FriendlyByteBuf` overloads are `readBuffer` / `writeBuffer`. The block entity a point is
// attached to is an [Object] (the host's `CreateBlockEntity`); the pure code reaches it only
// through [EdgePointHooks].
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/data.dart';
import '../../common/pos.dart';
import '../../core/byte_buf.dart';
import '../graph/dimension_palette.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../manager/create.dart';
import '../observer/filter_item_stack.dart';
import '../util/ctag.dart';

/// What the pure code knows of the block entity that targets an edge point.
final class EdgePointOwnerInfo {
  final Pos pos;
  final String worldId;

  /// The block state values of the block at [pos] (`BlockState.getValue`), as text.
  final Map<String, String> properties;

  const EdgePointOwnerInfo(this.pos, this.worldId, [this.properties = const {}]);
}

/// The few places where the pure edge points reach into the host. The trains module installs
/// them (`graph_registration.dart`); tests may install fakes.
abstract final class EdgePointHooks {
  /// Describes a block entity (`getBlockPos()`, `getLevel().dimension()`, `getBlockState()`).
  /// The default understands [EdgePointOwnerInfo] only.
  static EdgePointOwnerInfo Function(Object blockEntity) describe = (be) =>
      be is EdgePointOwnerInfo ? be : throw ArgumentError('Unknown block entity $be');

  /// `blockEntity instanceof SignalBlockEntity ste && ste.getReportedPower()`.
  static bool Function(Object blockEntity) reportedPower = (_) => false;

  /// The filter of a track observer block entity (`FilteringBehaviour.getFilter()`), `null` when
  /// the block entity has no filtering behaviour.
  static FilterItemStack? Function(Object blockEntity) observerFilter = (_) => null;

  /// `BlockEntityBehaviour.get(level, pos, TrackTargetingBehaviour.TYPE)?.invalidateEdgePoint(data)`.
  static void Function(Object? level, String worldId, Pos pos, CTag migrationData)? invalidateTargeting;
}

abstract class TrackEdgePoint {
  late String id;
  late Couple<TrackNodeLocation> edgeLocation;
  double position = 0;
  EdgePointType<TrackEdgePoint>? _type;

  void setId(String id) => this.id = id;

  String getId() => id;

  void setType(EdgePointType<TrackEdgePoint> type) => _type = type;

  EdgePointType<TrackEdgePoint> getType() => _type!;

  bool canMerge();

  bool canCoexistWith(EdgePointType<TrackEdgePoint> otherType, bool front) => false;

  /// [level] is whatever the caller has as a level (the world, `null` when not available).
  void invalidate(Object? level);

  /// `invalidateAt(level, blockEntityPos)`; [worldId] is the dimension of the block entity.
  void invalidateAt(Object? level, String worldId, Pos blockEntityPos) {
    final hook = EdgePointHooks.invalidateTargeting;
    if (hook == null) return;
    final migrationData = CTag();
    final dimensions = DimensionPalette();
    write(migrationData, dimensions);
    dimensions.write(migrationData);
    hook(level, worldId, blockEntityPos, migrationData);
  }

  void blockEntityAdded(Object blockEntity, bool front);

  void blockEntityRemoved(Pos blockEntityPos, bool front);

  void onRemoved(TrackGraph graph) {}

  void setLocation(Couple<TrackNodeLocation> nodes, double position) {
    edgeLocation = nodes;
    this.position = position;
  }

  double getLocationOn(TrackEdge edge) => isPrimary(edge.node1) ? edge.getLength() - position : position;

  bool canNavigateVia(TrackNode side) => true;

  bool isPrimary(TrackNode node1) => edgeLocation.getSecond() == node1.getLocation();

  void read(CTag nbt, bool migration, DimensionPalette dimensions) {
    if (migration) return;
    id = nbt.getUuid('Id') ?? (throw const FormatException('TrackEdgePoint without Id'));
    position = nbt.getDouble('Position');
    final list = nbt.getCompoundList('Edge');
    edgeLocation = Couple<TrackNodeLocation>(
      TrackNodeLocation.read(list.isNotEmpty ? list[0] : CTag(), dimensions),
      TrackNodeLocation.read(list.length > 1 ? list[1] : CTag(), dimensions),
    );
  }

  /// `read(FriendlyByteBuf, dimensions)`: after the type identifier.
  void readBuffer(PacketReader buffer, DimensionPalette dimensions) {
    id = buffer.readUuid();
    final a = TrackNodeLocation.receive(buffer, dimensions);
    final b = TrackNodeLocation.receive(buffer, dimensions);
    edgeLocation = Couple<TrackNodeLocation>(a, b);
    position = buffer.readDouble();
  }

  void write(CTag nbt, DimensionPalette dimensions) {
    nbt.putUuid('Id', id);
    nbt.putDouble('Position', position);
    nbt.putCompoundList('Edge', [edgeLocation.first.write(dimensions), edgeLocation.second.write(dimensions)]);
  }

  /// `write(FriendlyByteBuf, dimensions)`: the type identifier first.
  void writeBuffer(PacketWriter buffer, DimensionPalette dimensions) {
    buffer.writeId(getType().getId());
    buffer.writeUuid(id);
    edgeLocation.first.send(buffer, dimensions);
    edgeLocation.second.send(buffer, dimensions);
    buffer.writeDouble(position);
  }

  void tick(TrackGraph graph, bool preTrains) {}

  void removeFromAllGraphs() {
    for (final trackGraph in Create.RAILWAYS.trackNetworks.values.toList()) {
      if (trackGraph.removePoint(getType(), id) != null) return;
    }
  }
}
