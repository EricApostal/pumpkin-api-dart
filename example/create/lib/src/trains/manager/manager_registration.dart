// Registration of the railway manager for the trains module: the saved data of the overworld
// (`RailwaySavedData` as typed JSON), the `RailwayCommandHooks` of the infrastructure commands and
// the load of the railways when the server is up.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/infra.dart';
import '../../api/infra_data.dart';
import '../../common/vec_helper.dart' show Vec3;
import '../../core/module.dart';
import '../../core/registry.dart';
import '../../core/world_state.dart';
import '../entity/train.dart';
import '../graph/dimension_palette.dart' show overworldId;
import '../manager/create.dart';
import '../manager/global_railway_manager.dart';
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

/// Phase 2: the storage, the command hooks and the load error logger.
void loadManager(CreateContext ctx) {
  Create.RAILWAYS.storage = _RailwayStorage(ctx);
  RailwaySavedData.onLoadError = (what, error, stack) => ctx.log.warn(
    'Could not read $what of the railways',
    error: error,
    stackTrace: stack,
  );
  ctx.services.provide<RailwayCommandHooks>(_RailwayHooks());
}

/// Phase 3: the overworld's data exists now.
void serverManagerLoaded(CreateRuntime runtime) =>
    Create.RAILWAYS.overworldLoaded();

/// Plugin unload.
void unloadManager() {
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
    return RailwaySummary(
      graphCount: manager.trackNetworks.length,
      signalGroupCount: manager.signalEdgeGroups.length,
      trainCount: manager.trains.length,
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
