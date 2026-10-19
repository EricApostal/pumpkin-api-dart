// `LazyTickedScheduleCondition` (pure): a condition that is only evaluated every [tickRate] ticks.
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';

abstract class LazyTickedScheduleCondition extends ScheduleWaitCondition {
  final int tickRate;

  LazyTickedScheduleCondition(this.tickRate);

  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    var time = context.getInt('Time');
    if (time % tickRate == 0) {
      if (lazyTickCompletion(level, train, context)) return true;
      time = 0;
    }
    context.putInt('Time', time + 1);
    return false;
  }

  bool lazyTickCompletion(ScheduleLevel level, Train train, CTag context);
}
