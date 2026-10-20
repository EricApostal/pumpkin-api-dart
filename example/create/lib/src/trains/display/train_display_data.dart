// The trains module's [TrainDisplayData] provider: the three train display-link sources
// (`observed_train_name`, `train_status`, `station_summary`) read the trains module through it.
// Java reads the same state from the block entities directly (`ObservedTrainNameSource.java:17-30`,
// `TrainStatusDisplaySource.java:64-85`, `StationSummaryDisplaySource` -> `GlobalTrainDisplayData`).
import '../../api/redstone.dart' show TrainDisplayData, TrainPredictionView;
import '../../api/util.dart';
import '../../common/pos.dart';
import '../../core/block_entity.dart';
import '../../redstone/support/text.dart' show Txt;
import '../manager/create.dart';
import '../manager/global_railway_manager.dart' show RailwayHooks;
import '../manager/global_train_display_data.dart' show GlobalTrainDisplayData;
import '../observer/track_observer_block_entity.dart';
import '../schedule/schedule_runtime.dart' show State;
import '../station/station_block_entity.dart';
import '../support/runtime.dart';

/// `TrainDisplayData` over the loaded block entities and [GlobalTrainDisplayData].
final class HostTrainDisplayData implements TrainDisplayData {
  const HostTrainDisplayData();

  @override
  Txt? observedTrainName(String worldId, Pos pos) {
    final observer = _be<TrackObserverBlockEntity>(worldId, pos)?.getObserver();
    if (observer == null) return null;
    final currentTrain = observer.getCurrentTrain();
    if (currentTrain == null) return null;
    final train = Create.RAILWAYS.trains[currentTrain];
    if (train == null) return null;
    // `train.name.copy()`: the source may label the line, so it gets its own component.
    return train.name.copy();
  }

  @override
  Txt? trainStatus(String worldId, Pos pos) {
    final station = _be<StationBlockEntity>(worldId, pos)?.getStation();
    if (station == null) return null;
    final train = station.getPresentTrain();
    if (train == null) return null;

    final runtime = train.runtime;
    final schedule = runtime.getSchedule();
    if (schedule == null) return null;
    if (runtime.paused) return null;
    if (runtime.state != State.POST_TRANSIT) return null;
    if (runtime.currentEntry == schedule.entries.length - 1 &&
        !schedule.cyclic) {
      return null;
    }

    final level = RailwayHooks.trainLevelById?.call(worldId);
    if (level == null) return null;
    return runtime.getWaitingStatus(level);
  }

  @override
  String? stationName(String worldId, Pos pos) =>
      _be<StationBlockEntity>(worldId, pos)?.getStation()?.name;

  @override
  List<TrainPredictionView> predictions(String filter, int maxRows) => [
    for (final p in GlobalTrainDisplayData.prepare(filter, maxRows))
      TrainPredictionView(
        p.ticks,
        p.train.name.copy(),
        p.scheduleTitle,
        p.destination,
      ),
  ];

  /// The block entity at [pos] when its type is [T], else `null`.
  ///
  /// Java tests the block entity of the source position (`context.getSourceBlockEntity()`) against
  /// the expected class; the store lookup is the same question.
  T? _be<T extends CreateBlockEntity>(String worldId, Pos pos) {
    if (!Tr.loaded) return null;
    return Tr.i.store.typed<T>(worldId, pos.toBlockPos());
  }
}
