// `TimedWaitCondition` (pure): the base of the conditions that count ticks.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import '../schedule_math.dart';
import 'schedule_wait_condition.dart';

// ignore_for_file: constant_identifier_names

/// `TimedWaitCondition.TimeUnit`.
enum TimeUnit {
  TICKS(1, 't', 'generic.unit.ticks'),
  SECONDS(20, 's', 'generic.unit.seconds'),
  MINUTES(20 * 60, 'min', 'generic.unit.minutes');

  final int ticksPer;
  final String suffix;
  final String key;

  const TimeUnit(this.ticksPer, this.suffix, this.key);
}

abstract class TimedWaitCondition extends ScheduleWaitCondition {
  TimedWaitCondition() {
    data.putInt('Value', 5);
    data.putInt('TimeUnit', TimeUnit.SECONDS.index);
  }

  /// `requestDisplayIfNecessary(context, time)`.
  void requestDisplayIfNecessary(CTag context, int time) {
    final ticksUntilDeparture = totalWaitTicks() - time;
    if (ticksUntilDeparture < 20 * 60 && ticksUntilDeparture % 100 == 0) requestStatusToUpdate(context);
    if (ticksUntilDeparture >= 20 * 60 && ticksUntilDeparture % (20 * 60) == 0) requestStatusToUpdate(context);
  }

  /// `totalWaitTicks()`.
  int totalWaitTicks() => getValue() * getUnit().ticksPer;

  int getValue() => intData('Value');

  TimeUnit getUnit() => enumData('TimeUnit', TimeUnit.values);

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) {
    final time = tag.getInt('Time');
    final ticksUntilDeparture = totalWaitTicks() - time;
    final showInMinutes = ticksUntilDeparture >= 20 * 60;
    final ticks = toFloat32(ticksUntilDeparture.toDouble());
    final num =
        (showInMinutes ? toFloat32(ticks / (20 * 60)).floorToDouble() : toFloat32(ticks / 100).ceilToDouble() * 5)
            .toInt();
    final key =
        'generic.${showInMinutes ? (num == 1 ? 'daytime.minute' : 'unit.minutes') : (num == 1 ? 'daytime.second' : 'unit.seconds')}';
    final path = getId().split(':').last;
    return translateDirect('schedule.condition.$path.status', [Txt.literal('$num ').append(translateDirect(key))]);
  }
}
