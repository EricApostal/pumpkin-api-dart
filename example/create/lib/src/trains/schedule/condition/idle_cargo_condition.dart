// `IdleCargoCondition` (pure): wait until nothing was loaded or unloaded for a while.
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_level.dart';
import 'timed_wait_condition.dart';

class IdleCargoCondition extends TimedWaitCondition {
  /// `Integer.MAX_VALUE`.
  static const int _intMax = 2147483647;

  @override
  String getId() => 'create:idle';

  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    var idleTime = _intMax;
    for (final carriage in train.carriages) {
      final ticks = carriage.storage.getTicksSinceLastExchange();
      if (ticks < idleTime) idleTime = ticks;
    }
    context.putInt('Time', idleTime);
    requestDisplayIfNecessary(context, idleTime);
    return idleTime > totalWaitTicks();
  }
}
