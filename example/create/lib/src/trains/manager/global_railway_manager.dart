// `GlobalRailwayManager` (pure): the one registry of graphs, signal edge groups and trains. The
// tick, the sync, the login hook and the clean up are the Java ones; where Java reads the server
// (`MinecraftServer`, the data storage of the overworld) the host glue hands in a [RailwayStorage].
import '../entity/train.dart';
import '../entity/train_level.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_graph.dart';
import '../graph/track_graph_sync.dart';
import '../graph/track_node_location.dart';
import '../signal/edge_group_color.dart';
import '../signal/signal_edge_group.dart';
import 'global_train_display_data.dart';
import 'railway_saved_data.dart';

/// Where the railway data is kept (`RailwaySavedData.load(server)`).
abstract interface class RailwayStorage {
  /// The saved data of the overworld, loaded on first use.
  RailwaySavedData load();
}

/// The few things of a player that the manager sends individually.
abstract final class RailwayHooks {
  /// `NetworkHelper.INSTANCE.sendToClient(player, new AddTrainPacket(train))`.
  static void Function(Object player, Train train)? sendAddTrainTo;

  /// The [TrainLevel] of a host world (the argument is the world), `null` for none. Installed by
  /// the host glue; the overworld's one is what the railways tick with.
  static TrainLevel? Function(Object world)? trainLevelFactory;

  /// The [TrainLevel] of the loaded dimension [worldId], `null` when it is not loaded.
  static TrainLevel? Function(String worldId)? trainLevelById;
}

class GlobalRailwayManager {
  late Map<String, TrackGraph> trackNetworks;
  late Map<String, SignalEdgeGroup> signalEdgeGroups;
  late Map<String, Train> trains;
  late TrackGraphSync sync;

  late List<Train> _movingTrains;
  late List<Train> _waitingTrains;

  RailwaySavedData? savedData;

  /// Set by the host glue.
  RailwayStorage? storage;

  int version = 0;

  GlobalRailwayManager() {
    cleanUp();
  }

  /// `playerLogin(player)`: [player] is the host's player handle.
  void playerLogin(Object player) {
    loadTrackData();
    for (final g in trackNetworks.values) {
      sync.sendFullGraphTo(g, player);
    }

    final ids = <String>[];
    final colors = <EdgeGroupColor>[];
    for (final group in signalEdgeGroups.values) {
      ids.add(group.id);
      colors.add(group.color);
    }
    sync.sendEdgeGroups(ids, colors, player);

    final send = RailwayHooks.sendAddTrainTo;
    if (send != null) {
      for (final train in trains.values) {
        send(player, train);
      }
    }
  }

  void playerLogout(Object player) {}

  /// `levelLoaded(level)` for the overworld.
  void overworldLoaded() {
    cleanUp();
    savedData = null;
    loadTrackData();
  }

  /// `loadTrackData(server)`.
  void loadTrackData() {
    if (savedData != null) return;
    final store = storage;
    if (store == null) return;
    final sd = store.load();
    savedData = sd;
    trains = sd.getTrains();
    trackNetworks = sd.getTrackNetworks();
    signalEdgeGroups = sd.getSignalBlocks();
    _movingTrains.addAll(trains.values);
  }

  void cleanUp() {
    trackNetworks = {};
    signalEdgeGroups = {};
    trains = {};
    sync = TrackGraphSync();
    _movingTrains = [];
    _waitingTrains = [];
    GlobalTrainDisplayData.statusByDestination.clear();
  }

  void markTracksDirty() {
    savedData?.setDirty();
  }

  void addTrain(Train train) {
    trains[train.id] = train;
    _movingTrains.add(train);
  }

  void removeTrain(String id) {
    final removed = trains.remove(id);
    if (removed == null) return;
    _movingTrains.remove(removed);
    _waitingTrains.remove(removed);
  }

  //

  TrackGraph getOrCreateGraph(String graphID, int netId) {
    return trackNetworks.putIfAbsent(graphID, () {
      final trackGraph = TrackGraph(graphID);
      trackGraph.setNetId(netId);
      return trackGraph;
    });
  }

  void putGraphWithDefaultGroup(TrackGraph graph) {
    final group = SignalEdgeGroup(graph.id);
    signalEdgeGroups[graph.id] = group.asFallback();
    sync.edgeGroupCreated(graph.id, group.color);
    putGraph(graph);
  }

  void putGraph(TrackGraph graph) {
    trackNetworks[graph.id] = graph;
    markTracksDirty();
  }

  void removeGraphAndGroup(TrackGraph graph) {
    signalEdgeGroups.remove(graph.id);
    sync.edgeGroupRemoved(graph.id);
    removeGraph(graph);
  }

  void removeGraph(TrackGraph graph) {
    trackNetworks.remove(graph.id);
    markTracksDirty();
  }

  /// `updateSplitGraph(level, graph)`.
  void updateSplitGraph(Object? level, TrackGraph graph) {
    final disconnected = graph.findDisconnectedGraphs(level, null);
    for (final d in disconnected) {
      putGraphWithDefaultGroup(d);
    }
    if (disconnected.isNotEmpty) {
      sync.graphSplit(graph, disconnected);
      markTracksDirty();
    }
  }

  /// `getGraph(level, vertex)`: the graph that has a node at [vertex].
  TrackGraph? getGraph(Object? level, TrackNodeLocation vertex) {
    for (final railGraph in trackNetworks.values) {
      if (railGraph.locateNode(vertex) != null) return railGraph;
    }
    return null;
  }

  List<TrackGraph> getGraphs(Object? level, TrackNodeLocation vertex) {
    final intersecting = <TrackGraph>[];
    for (final railGraph in trackNetworks.values) {
      if (railGraph.locateNode(vertex) != null) intersecting.add(railGraph);
    }
    return intersecting;
  }

  /// `tick(level)`: runs once per tick, from the overworld's tick.
  void tick(TrainLevel level) {
    if (level.dimension != overworldId) return;

    for (final group in signalEdgeGroups.values) {
      group.trains.clear();
      group.reserved = null;
    }

    for (final graph in trackNetworks.values.toList()) {
      graph.tickPoints(true);
      graph.resolveIntersectingEdgeGroups(level);
    }

    _tickTrains(level);

    for (final graph in trackNetworks.values.toList()) {
      graph.tickPoints(false);
    }

    GlobalTrainDisplayData.updateTick = level.gameTime % 100 == 0;
    if (GlobalTrainDisplayData.updateTick) GlobalTrainDisplayData.refresh();
  }

  void _tickTrains(TrainLevel level) {
    // keeping two lists ensures a tick order starting at longest waiting
    for (final train in _waitingTrains.toList()) {
      train.earlyTick(level);
    }
    for (final train in _movingTrains.toList()) {
      train.earlyTick(level);
    }
    for (final train in _waitingTrains.toList()) {
      train.tick(level);
    }
    for (final train in _movingTrains.toList()) {
      train.tick(level);
    }

    for (final train in _waitingTrains.toList()) {
      if (train.invalid) {
        _waitingTrains.remove(train);
        trains.remove(train.id);
        TrainFx.effects.sendRemoveTrain(train.id);
        continue;
      }

      if (train.navigation.waitingForSignal != null) continue;
      _movingTrains.add(train);
      _waitingTrains.remove(train);
    }

    for (final train in _movingTrains.toList()) {
      if (train.invalid) {
        _movingTrains.remove(train);
        trains.remove(train.id);
        TrainFx.effects.sendRemoveTrain(train.id);
        continue;
      }

      if (train.navigation.waitingForSignal == null) continue;
      _waitingTrains.add(train);
      _movingTrains.remove(train);
    }
  }

  /// `sided(level)`: the server has one manager.
  GlobalRailwayManager sided(Object? level) => this;

  /// The trains in tick order (moving trains; for tests).
  List<Train> get movingTrains => List.unmodifiable(_movingTrains);

  /// The trains that wait for a signal (for tests).
  List<Train> get waitingTrains => List.unmodifiable(_waitingTrains);
}
