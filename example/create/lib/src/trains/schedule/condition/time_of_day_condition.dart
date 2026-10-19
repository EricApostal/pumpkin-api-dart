// `TimeOfDayCondition` (pure): wait for a time of the day, repeating every rotation.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';
import '../schedule_math.dart';

class TimeOfDayCondition extends ScheduleWaitCondition {
  TimeOfDayCondition() {
    data.putInt('Hour', 8);
    data.putInt('Rotation', 5);
  }

  /// `(int) ((((hour + 18) % 24) * 1000 + Math.ceil(minute / 60f * 1000)) % rotation)`.
  int targetTicks(int rotation) {
    final targetHour = intData('Hour');
    final targetMinute = intData('Minute');
    final minuteTicks = toFloat32(toFloat32(toFloat32(targetMinute.toDouble()) / 60) * 1000).ceilToDouble();
    final total = ((targetHour + 18) % 24) * 1000 + minuteTicks;
    return total.remainder(rotation).toInt();
  }

  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    const maxTickDiff = 40;
    final rotation = getRotation();
    final dayTime = level.overworldClockTime % rotation;
    final diff = dayTime - targetTicks(rotation);
    return diff >= 0 && maxTickDiff >= diff;
  }

  /// `getRotation()`.
  int getRotation() {
    final index = intData('Rotation');
    return switch (index) {
      9 => 250,
      8 => 500,
      7 => 750,
      6 => 1000,
      5 => 2000,
      4 => 3000,
      3 => 4000,
      2 => 6000,
      1 => 12000,
      _ => 24000,
    };
  }

  /// `getDigitalDisplay(hour, minute, doubleDigitHrs)`.
  Txt getDigitalDisplay(int hour, int minute, bool doubleDigitHrs) {
    final hour12raw = hour % 12 == 0 ? 12 : hour % 12;
    final hr12 = doubleDigitHrs ? twoDigits(hour12raw) : '$hour12raw';
    final hr24 = doubleDigitHrs ? twoDigits(hour) : '$hour';
    return translateDirect('schedule.condition.time_of_day.digital_format', [
      hr12,
      hr24,
      twoDigits(minute),
      translateDirect(hour > 11 ? 'generic.daytime.pm' : 'generic.daytime.am'),
    ]);
  }

  String twoDigits(int t) => t < 10 ? '0$t' : '$t';

  @override
  String getId() => 'create:time_of_day';

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) {
    final rotation = getRotation();
    final clock = level.overworldClockTime;
    final dayTime = clock % rotation;
    var diff = targetTicks(rotation) - dayTime;

    if (diff < 0) diff += rotation;

    final departureTime = (clock + diff).toSigned(32).remainder(24000);
    final departingHour = (departureTime ~/ 1000 + 6).remainder(24);
    final departingMinute = departureTime.remainder(1000) * 60 ~/ 1000;

    return translateDirect('schedule.condition.time_of_day.status')
        .append(getDigitalDisplay(departingHour, departingMinute, false));
  }
}
