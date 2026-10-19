// `RailwaySavedData` (pure): everything the railways persist (graphs, signal edge groups, trains) as
// one NBT compound, stored as typed JSON in the overworld's saved data (see `manager_registration.dart`).
// The Java class is a `SavedData` of the overworld's data storage; here the host glue provides
// [onDirty] and [type].
import '../entity/train.dart';
import '../graph/dimension_palette.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_graph.dart';
import '../signal/signal_edge_group.dart';
import '../util/ctag.dart';

class RailwaySavedData {
  Map<String, TrackGraph> trackNetworks = {};
  Map<String, SignalEdgeGroup> signalEdgeGroups = {};
  Map<String, Train> trains = {};

  /// Called by [setDirty]; the host glue queues the data for writing.
  void Function()? onDirty;

  /// Called with a description when an entry of the saved data cannot be read (it is skipped).
  static void Function(String what, Object error, StackTrace stack)? onLoadError;

  RailwaySavedData();

  void setDirty() => onDirty?.call();

  /// `save(nbt, registries)`: writes this data (the maps the manager works on) into [nbt].
  CTag save(CTag nbt) {
    final dimensions = DimensionPalette();
    nbt.putCompoundList('RailGraphs', [for (final tg in trackNetworks.values) tg.write(dimensions)]);
    nbt.putCompoundList('SignalBlocks', [
      for (final seg in signalEdgeGroups.values)
        if (!(seg.fallbackGroup && !trackNetworks.containsKey(seg.id))) seg.write(),
    ]);
    nbt.putCompoundList('Trains', [for (final t in trains.values) t.write(dimensions)]);
    dimensions.write(nbt);
    return nbt;
  }

  /// `load(nbt, registries)`.
  static RailwaySavedData load(CTag nbt) {
    final sd = RailwaySavedData();

    final dimensions = DimensionPalette.read(nbt);
    // Java lets a bad entry fail the whole load; the plugin keeps the rest instead.
    for (final c in nbt.getCompoundList('RailGraphs')) {
      try {
        final graph = TrackGraph.read(c, dimensions);
        sd.trackNetworks[graph.id] = graph;
      } on Object catch (e, s) {
        onLoadError?.call('a track graph', e, s);
      }
    }
    for (final c in nbt.getCompoundList('SignalBlocks')) {
      try {
        final group = SignalEdgeGroup.read(c);
        sd.signalEdgeGroups[group.id] = group;
      } on Object catch (e, s) {
        onLoadError?.call('a signal edge group', e, s);
      }
    }
    for (final c in nbt.getCompoundList('Trains')) {
      try {
        final train = Train.read(c, sd.trackNetworks, dimensions);
        sd.trains[train.id] = train;
      } on Object catch (e, s) {
        onLoadError?.call('a train', e, s);
      }
    }

    for (final graph in sd.trackNetworks.values) {
      for (final signal in graph.getPoints(EdgePointType.SIGNAL)) {
        final groupId = signal.groups.getFirst();
        final otherGroupId = signal.groups.getSecond();
        if (groupId == null || otherGroupId == null) continue;
        final group = sd.signalEdgeGroups[groupId];
        final otherGroup = sd.signalEdgeGroups[otherGroupId];
        if (group == null || otherGroup == null) continue;
        group.putAdjacent(otherGroupId);
        otherGroup.putAdjacent(groupId);
      }
    }

    return sd;
  }

  Map<String, TrackGraph> getTrackNetworks() => trackNetworks;

  Map<String, Train> getTrains() => trains;

  Map<String, SignalEdgeGroup> getSignalBlocks() => signalEdgeGroups;

  /// The lossless JSON form (the saved data of the world).
  Map<String, dynamic> toMap() => save(CTag()).toJson();

  static RailwaySavedData fromMap(Map<String, dynamic> map) => load(CTag.fromJson(map));
}
