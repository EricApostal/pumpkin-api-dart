// `StationUnloadedCondition` (pure): wait until the station's chunk stopped ticking.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';

class StationUnloadedCondition extends ScheduleWaitCondition {
  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    final currentStation = train.getCurrentStation();
    if (currentStation == null) return false;
    final stationDim = currentStation.getBlockEntityDimension();
    final stationPos = currentStation.getBlockEntityPos();
    if (stationPos == null) return false;
    if (!level.hasServer) return false;
    if (!level.hasDimension(stationDim)) return false;
    return !level.isPositionEntityTicking(stationDim, stationPos);
  }

  @override
  void writeAdditional(CTag tag) {}

  @override
  void readAdditional(CTag tag) {}

  @override
  String getId() => 'create:unloaded';

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) =>
      translateDirect('schedule.condition.unloaded.status');
}
