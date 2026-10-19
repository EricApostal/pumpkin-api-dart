// `StationPoweredCondition` (pure): wait until the station block receives a redstone signal.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';

class StationPoweredCondition extends ScheduleWaitCondition {
  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    final currentStation = train.getCurrentStation();
    if (currentStation == null) return false;
    final stationPos = currentStation.getBlockEntityPos();
    final stationDim = currentStation.getBlockEntityDimension();
    if (stationPos == null) return false;
    if (!level.hasServer) return false;
    if (!level.hasDimension(stationDim) || !level.isLoaded(stationDim, stationPos)) return false;
    return level.hasNeighborSignal(stationDim, stationPos);
  }

  @override
  void writeAdditional(CTag tag) {}

  @override
  void readAdditional(CTag tag) {}

  @override
  String getId() => 'create:powered';

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) =>
      translateDirect('schedule.condition.powered.status');
}
