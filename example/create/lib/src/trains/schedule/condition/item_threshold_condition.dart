// `ItemThresholdCondition` (pure): wait until the train holds more / less / exactly some items.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'cargo_threshold_condition.dart';

class ItemThresholdCondition extends CargoThresholdCondition {
  /// `FilterItemStack stack` in its NBT form (`FilterItemStack.serializeNBT`); empty for no filter.
  CTag stack = CTag();

  @override
  bool test(ScheduleLevel level, Train train, CTag context) {
    final operator = getOperator();
    final target = getThreshold();
    final stacks = inStacks();

    var foundItems = 0;
    for (final carriage in train.carriages) {
      final cargo = carriage.storage;
      for (final stackInSlot in cargo.getAllItems()) {
        if (!level.filters.testItem(stack, stackInSlot)) continue;

        if (stacks) {
          foundItems += stackInSlot.count == stackInSlot.maxStackSize ? 1 : 0;
        } else {
          foundItems += stackInSlot.count;
        }
      }
    }

    requestStatusToUpdateAmount(foundItems, context);
    return operator.test(foundItems, target);
  }

  @override
  void writeAdditional(CTag tag) {
    tag.putCompound('Item', stack.copy());
  }

  @override
  void readAdditional(CTag tag) {
    if (tag.contains('Item')) stack = tag.getCompound('Item').copy();
  }

  @override
  void setItem(int slot, CTag stack) {
    this.stack = stack.copy();
  }

  @override
  CTag getItem(int slot) => stack;

  bool inStacks() => intData('Measure') == 1;

  @override
  String getId() => 'create:item_threshold';

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) {
    final lastDisplaySnapshot = getLastDisplaySnapshot(tag);
    if (lastDisplaySnapshot == -1) return Txt.empty();
    final offset = getOperator() == Ops.LESS ? -1 : (getOperator() == Ops.GREATER ? 1 : 0);
    final threshold = getThreshold() + offset;
    return translateDirect('schedule.condition.threshold.status', [
      lastDisplaySnapshot,
      threshold < 0 ? 0 : threshold,
      translateDirect('schedule.condition.threshold.${inStacks() ? 'stacks' : 'items'}'),
    ]);
  }
}
