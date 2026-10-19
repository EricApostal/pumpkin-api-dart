// `ScheduleWaitCondition` (pure): something a train waits for at a station before it departs.
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../../../redstone/support/text.dart' show Txt;
import '../destination/schedule_instruction.dart' show normalizeIdentifier;
import '../schedule.dart';
import '../schedule_data_entry.dart';
import '../schedule_level.dart';

abstract class ScheduleWaitCondition extends ScheduleDataEntry {
  ScheduleWaitCondition();

  /// `tickCompletion(level, train, context)`: true when the condition is fulfilled. [context] is
  /// the per condition state the runtime keeps (`ConditionContext`).
  bool tickCompletion(ScheduleLevel level, Train train, CTag context);

  /// `requestStatusToUpdate(context)`: bumps `StatusVersion` so display links refresh.
  void requestStatusToUpdate(CTag context) {
    context.putInt('StatusVersion', context.getInt('StatusVersion') + 1);
  }

  /// `write(registries)`: `{Id, Data}`.
  CTag write() {
    final tag = CTag();
    final dataCopy = data.copy();
    writeAdditional(dataCopy);
    tag.putString('Id', getId());
    tag.putCompound('Data', dataCopy);
    return tag;
  }

  /// `fromTag(registries, tag)`; `null` for an unknown id.
  static ScheduleWaitCondition? fromTag(CTag tag) {
    final location = normalizeIdentifier(tag.getString('Id'));
    ScheduleWaitCondition Function()? supplier;
    for (final pair in Schedule.CONDITION_TYPES) {
      if (pair.first == location) supplier = pair.second;
    }
    if (supplier == null) return null;

    final condition = supplier();
    // Left around for migration purposes. Data added in writeAdditional has moved into the "Data" tag
    condition.readAdditional(tag);
    final data = tag.getCompound('Data');
    condition.readAdditional(data);
    condition.data = data;
    return condition;
  }

  /// `getWaitingStatus(level, train, tag)`: the text a display link shows while waiting.
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag);
}
