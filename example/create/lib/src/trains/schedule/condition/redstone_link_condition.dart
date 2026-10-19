// `RedstoneLinkCondition` (pure): wait until a redstone link network of two frequencies is
// powered (or unpowered).
import '../../../common/data.dart' show Couple;
import '../../../redstone/link/frequency.dart' show Frequency;
import '../../../redstone/support/text.dart' show Txt;
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_lang.dart';
import '../schedule_level.dart';
import 'schedule_wait_condition.dart';

class RedstoneLinkCondition extends ScheduleWaitCondition {
  /// `public Couple<Frequency> freq`.
  Couple<Frequency> freq = Couple.fromFactory(() => Frequency.empty);

  /// The frequency stacks as they were stored (`ItemStack.CODEC` NBT), written back as they are.
  final Couple<CTag> _stacks = Couple.fromFactory(CTag.new);

  @override
  int slotsTargeted() => 2;

  @override
  bool tickCompletion(ScheduleLevel level, Train train, CTag context) {
    final handler = level.redstoneLinks;
    if (handler == null) return false;
    final lastChecked = context.contains('LastChecked') ? context.getInt('LastChecked') : -1;
    final status = handler.globalPowerVersion;
    if (status == lastChecked) return false;
    context.putInt('LastChecked', status);
    return handler.hasAnyLoadedPower(freq) != lowActivation();
  }

  @override
  void setItem(int slot, CTag stack) {
    final first = slot == 0;
    freq.set(first, frequencyOfItemTag(stack));
    final one = stack.copy();
    if (one.contains('id')) one.putInt('count', 1);
    _stacks.set(first, one);
  }

  @override
  CTag getItem(int slot) => _stacks.get(slot == 0);

  @override
  String getId() => 'create:redstone_link';

  @override
  void writeAdditional(CTag tag) {
    tag.putCompoundList('Frequency', [_stacks.first.copy(), _stacks.second.copy()]);
  }

  bool lowActivation() => intData('Inverted') == 1;

  @override
  void readAdditional(CTag tag) {
    if (tag.contains('Frequency')) {
      final list = tag.getCompoundList('Frequency');
      final first = list.isNotEmpty ? list[0].copy() : CTag();
      final second = list.length > 1 ? list[1].copy() : CTag();
      _stacks.first = first;
      _stacks.second = second;
      freq = Couple(frequencyOfItemTag(first), frequencyOfItemTag(second));
    }
  }

  @override
  Txt getWaitingStatus(ScheduleLevel level, Train train, CTag tag) =>
      translateDirect('schedule.condition.redstone_link.status');
}

/// `Frequency.of(stack)` for a stack in its NBT form (`{id, count, components}`): the item and the
/// `minecraft:dyed_color` of the components.
Frequency frequencyOfItemTag(CTag stack) {
  if (stack.isEmpty) return Frequency.empty;
  final id = stack.getString('id');
  if (id.isEmpty) return Frequency.empty;
  final components = stack.getCompoundOrNull('components');
  return Frequency.of(
    id.contains(':') ? id : 'minecraft:$id',
    color: components?.getIntOr('minecraft:dyed_color', -1) ?? -1,
  );
}
