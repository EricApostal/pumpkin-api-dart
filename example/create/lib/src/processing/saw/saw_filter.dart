// `FilteringBehaviour` of the mechanical saw (`SawBlockEntity.filtering`, `forRecipes()`): one
// item that decides which recipe results the saw may produce. The host does not route the value
// box's short interaction to behaviours that are not value settings targets, so the saw's block
// use handler sets the filter when the top slot is clicked (see `saw_block.dart`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';

/// The filter slot of the saw.
class SawFilterBehaviour extends BlockEntityBehaviour {
  static const String type = 'saw_filter';

  @override
  String get id => type;

  /// The filter stack (one item); empty matches everything.
  PStack filter = PStack.empty;

  /// `FilteringBehaviour.count` / `upTo`: written with the filter even though the saw's value box
  /// does not show the count (kept for NBT parity with `FilteringBehaviour`).
  int count = 64;
  bool upTo = true;

  /// `FilteringBehaviour.getMaxStackSize()`.
  int get maxStackSize => filter.isEmpty ? 64 : filter.maxStack;

  /// `FilteringBehaviour.test`: the recipe result passes when the filter is empty or names the
  /// same item.
  bool test(PStack stack) => filter.isEmpty || stack.key == filter.key;

  /// `setFilter`.
  void setFilter(PStack stack) {
    filter = stack.isEmpty ? PStack.empty : stack.withCount(1);
    owner.sendData();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    filter = StackNbt.read(tag.getCompound('Filter'));
    count = tag.getInt('FilterAmount') ?? 0;
    upTo = tag.getBool('UpTo') ?? false;
    // `FilteringBehaviour.read`: migrate data written before the count existed.
    if (count == 0) {
      upTo = true;
      count = maxStackSize;
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Filter', StackNbt.writeOrEmpty(filter));
    tag.putInt('FilterAmount', count);
    tag.putBool('UpTo', upTo);
  }
}
