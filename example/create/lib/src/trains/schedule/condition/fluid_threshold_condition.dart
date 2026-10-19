// `FluidThresholdCondition` (pure): wait until the train holds more / less / exactly some buckets.
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'cargo_threshold_condition.dart';

class FluidThresholdCondition extends CargoThresholdCondition {
  /// `FilterItemStack compareStack` in its NBT form; empty for no filter.
  CTag compareStack = CTag();

  @override
  bool test(ScheduleLevel level, Train train, CTag context) {
    final operator = getOperator();
    final target = getThreshold();

    var foundFluid = 0;
    for (final carriage in train.carriages) {
      final cargo = carriage.storage;
      for (final fluidInTank in cargo.getFluids()) {
        if (!level.filters.testFluid(compareStack, fluidInTank)) continue;
        foundFluid += fluidInTank.amount;
      }
    }

    requestStatusToUpdateAmount(foundFluid ~/ 1000, context);
    return operator.test(foundFluid, (target * 1000).toSigned(32));
  }

  @override
  void writeAdditional(CTag tag) {
    tag.putCompound('Bucket', compareStack.copy());
  }

  @override
  void readAdditional(CTag tag) {
    if (tag.contains('Bucket')) compareStack = tag.getCompound('Bucket').copy();
  }

  @override
  void setItem(int slot, CTag stack) {
    compareStack = stack.copy();
  }

  @override
  CTag getItem(int slot) => compareStack;

  @override
  String getId() => 'create:fluid_threshold';

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) {
    final lastDisplaySnapshot = getLastDisplaySnapshot(tag);
    if (lastDisplaySnapshot == -1) return Txt.empty();
    final offset = getOperator() == Ops.LESS ? -1 : (getOperator() == Ops.GREATER ? 1 : 0);
    final threshold = getThreshold() + offset;
    return translateDirect('schedule.condition.threshold.status', [
      lastDisplaySnapshot,
      threshold < 0 ? 0 : threshold,
      translateDirect('schedule.condition.threshold.buckets'),
    ]);
  }
}
