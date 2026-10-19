// `MillstoneBlockEntity.MillstoneInventoryHandler`: the combined input (1 slot) and output
// (9 slots) view that hoppers and belts see. Items may only go into the input, and only when
// the millstone has a recipe for them; items may only be taken out of the output.
import '../common/stack.dart';
import '../common/storage.dart';

final class MillstoneStorage implements ItemStorage {
  final ItemStorage input;
  final ItemStorage output;

  /// `canProcess(stack)`: whether the milling recipes know the item.
  final bool Function(PStack stack) canProcess;

  MillstoneStorage(this.input, this.output, {required this.canProcess});

  @override
  int get slots => input.slots + output.slots;

  bool _isInput(int slot) => slot < input.slots;

  @override
  PStack stackIn(int slot) =>
      _isInput(slot) ? input.stackIn(slot) : output.stackIn(slot - input.slots);

  @override
  int slotLimit(int slot) => _isInput(slot)
      ? input.slotLimit(slot)
      : output.slotLimit(slot - input.slots);

  @override
  bool isItemValid(int slot, PStack stack) =>
      _isInput(slot) && canProcess(stack) && input.isItemValid(slot, stack);

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    if (!_isInput(slot) || !isItemValid(slot, stack)) return stack;
    return input.insert(slot, stack, simulate: simulate);
  }

  @override
  PStack extract(int slot, int amount, {bool simulate = false}) {
    if (_isInput(slot)) return PStack.empty;
    return output.extract(slot - input.slots, amount, simulate: simulate);
  }
}
