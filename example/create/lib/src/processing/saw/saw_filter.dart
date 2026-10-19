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
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Filter', StackNbt.write(filter));
  }
}
