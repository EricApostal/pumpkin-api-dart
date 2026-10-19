// `ScheduledDelay` (pure): wait for a fixed time.
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_level.dart';
import 'timed_wait_condition.dart';

class ScheduledDelay extends TimedWaitCondition {
  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    final time = context.getInt('Time');
    if (time >= totalWaitTicks()) return true;

    context.putInt('Time', time + 1);
    requestDisplayIfNecessary(context, time);
    return false;
  }

  @override
  String getId() => 'create:delay';
}
