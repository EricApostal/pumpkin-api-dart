// `PlayerPassengerCondition` (pure): wait for a number of players to sit in the train.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';

class PlayerPassengerCondition extends ScheduleWaitCondition {
  @override
  String getId() => 'create:player_count';

  int getTarget() => intData('Count');

  bool canOvershoot() => intData('Exact') != 0;

  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    final prev = context.getInt('PrevPlayerCount');
    final present = train.countPlayerPassengers();
    final target = getTarget();
    context.putInt('PrevPlayerCount', present);
    if (prev != present) requestStatusToUpdate(context);
    return canOvershoot() ? present >= target : present == target;
  }

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) =>
      translateDirect('schedule.condition.player_count.status', [train.countPlayerPassengers(), getTarget()]);
}
