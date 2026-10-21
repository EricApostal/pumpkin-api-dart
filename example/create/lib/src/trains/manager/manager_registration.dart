// Registration of the railway manager for the trains module: the saved data of the overworld
// (`RailwaySavedData` as typed JSON), the `RailwayCommandHooks` of the infrastructure commands and
// the load of the railways when the server is up.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/config.dart' show ConfigValue, CreateConfigs;
import '../../api/infra.dart';
import '../../common/vec_helper.dart' show Vec3;
import '../../core/module.dart';
import '../../core/registry.dart';
import '../../core/world_state.dart';
import '../entity/train.dart';
import '../entity/train_level.dart' show TrainSettings;
import '../graph/dimension_palette.dart' show overworldId;
import '../graph/edge_point_type.dart' show EdgePointType;
import '../manager/create.dart';
import '../manager/global_railway_manager.dart';
import '../manager/manager_host.dart';
import '../manager/railway_saved_data.dart';
import '../station/host_ops.dart' show plainTrainsText;

/// The saved data of the railways in the overworld.
final SavedDataType<RailwaySavedData> railwaySavedDataType =
    SavedDataType<RailwaySavedData>(
      'railways',
      create: RailwaySavedData.new,
      fromMap: RailwaySavedData.fromMap,
      toMap: (v) => v.toMap(),
    );

/// Phase 1: the manager has no registered content.
void registerManager(CreateRegistry registry) {}

/// Phase 2: the storage, the host network / tick hooks, the command hooks and the load error
/// logger.
void loadManager(CreateContext ctx) {
  Create.RAILWAYS.storage = _RailwayStorage(ctx);
  RailwaySavedData.onLoadError = (what, error, stack) => ctx.log.warn(
    'Could not read $what of the railways',
    error: error,
    stackTrace: stack,
  );
  ctx.services.provide<RailwayCommandHooks>(_RailwayHooks());
  _applyTrainSettings(ctx);
  installRailwayManager(ctx);
}

/// Copies `AllConfigs.server().trains` into [TrainSettings] and keeps it in step with runtime
/// config changes (`/create config`).
void _applyTrainSettings(CreateContext ctx) {
  final configs = ctx.services.find<CreateConfigs>();
  if (configs == null) return;
  final trains = configs.server.trains;
  final settings = TrainSettings.current;

  void copy() {
    settings
      ..trainsCauseDamage = trains.trainsCauseDamage.value
      ..maxTrackPlacementLength = trains.maxTrackPlacementLength.value
      ..maxAssemblyLength = trains.maxAssemblyLength.value
      ..maxBogeyCount = trains.maxBogeyCount.value
      ..manualTrainSpeedModifier = trains.manualTrainSpeedModifier.value
      ..trainTopSpeed = trains.trainTopSpeed.value
      ..trainTurningTopSpeed = trains.trainTurningTopSpeed.value
      ..trainAcceleration = trains.trainAcceleration.value
      ..poweredTrainTopSpeed = trains.poweredTrainTopSpeed.value
      ..poweredTrainTurningTopSpeed = trains.poweredTrainTurningTopSpeed.value
      ..poweredTrainAcceleration = trains.poweredTrainAcceleration.value;
  }

  copy();
  for (final value in <ConfigValue<Object>>[
    trains.trainsCauseDamage,
    trains.maxTrackPlacementLength,
    trains.maxAssemblyLength,
    trains.maxBogeyCount,
    trains.manualTrainSpeedModifier,
    trains.trainTopSpeed,
    trains.trainTurningTopSpeed,
    trains.trainAcceleration,
    trains.poweredTrainTopSpeed,
    trains.poweredTrainTurningTopSpeed,
    trains.poweredTrainAcceleration,
  ]) {
    value.onChange((_) => copy());
  }
}

/// Phase 3: the overworld's data exists now.
void serverManagerLoaded(CreateRuntime runtime) =>
    Create.RAILWAYS.overworldLoaded();

/// Plugin unload.
void unloadManager() {
  uninstallRailwayManager();
  RailwaySavedData.onLoadError = null;
  Create.RAILWAYS.cleanUp();
}

final class _RailwayStorage implements RailwayStorage {
  final CreateContext ctx;

  _RailwayStorage(this.ctx);

  @override
  RailwaySavedData load() {
    final world = ctx.worlds.byId(overworldId);
    if (world == null) return RailwaySavedData();
    final data = ctx.savedData.get(world, railwaySavedDataType);
    data.onDirty = () =>
        ctx.savedData.markDirty(world.getId(), railwaySavedDataType);
    return data;
  }
}

final class _RailwayHooks implements RailwayCommandHooks {
  @override
  RailwaySummary summarize(String worldId, Vec3 location) {
    final manager = Create.RAILWAYS;

    // `fillReport`: the five graphs and five trains nearest to the command source, by
    // `TrackGraph.distanceToLocationSqr` / `Train.distanceToLocationSqr`. The counts alone left
    // `/create trains` listing neither a node count, nor a station, nor a train - the report
    // rendered `Nearest Graphs: ` with nothing under it (DumpRailwaysCommand.java:66-137).
    final graphs = manager.trackNetworks.values.toList()
      ..sort(
        (a, b) => a
            .distanceToLocationSqr(worldId, location)
            .compareTo(b.distanceToLocationSqr(worldId, location)),
      );

    final level = RailwayHooks.trainLevelById?.call(worldId);
    final trains = level == null
        ? <Train>[]
        : (manager.trains.values.toList()
            ..sort(
              (a, b) => a
                  .distanceToLocationSqr(level, location)
                  .compareTo(b.distanceToLocationSqr(level, location)),
            ));

    return RailwaySummary(
      graphCount: manager.trackNetworks.length,
      signalGroupCount: manager.signalEdgeGroups.length,
      trainCount: manager.trains.length,
      nearestGraphs: [
        for (final graph in graphs.take(5))
          TrackGraphSummary(
            graph.id,
            graph.nodes.length,
            signalCount: graph.getPoints(EdgePointType.SIGNAL).length,
            stationCount: graph.getPoints(EdgePointType.STATION).length,
          ),
      ],
      nearestTrains: [for (final train in trains.take(5)) _summary(train)],
    );
  }

  @override
  TrainSummary? findTrain(String id) {
    final train = Create.RAILWAYS.trains[id];
    if (train == null) return null;
    return _summary(train);
  }

  @override
  bool removeTrain(String id) {
    final train = Create.RAILWAYS.trains[id];
    if (train == null) return false;
    train.invalid = true;
    return true;
  }

  TrainSummary _summary(Train train) => TrainSummary(
    id: train.id,
    name: plainTrainsText(train.name),
    carriageCount: train.carriages.length,
    derailed: train.derailed,
    graphId: train.graph?.id,
    ownerName: train.owner,
    currentStationName: train.getCurrentStation()?.name,
    destinationName: train.navigation.destination?.name,
    distanceToDestination: train.navigation.distanceToDestination,
    hasSchedule: train.runtime.getSchedule() != null,
    scheduleState: train.runtime.state.name,
    schedulePaused: train.runtime.paused,
  );
}
