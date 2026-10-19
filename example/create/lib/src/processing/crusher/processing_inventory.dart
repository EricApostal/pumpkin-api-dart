// `ProcessingInventory`: the single-input inventory of the crushing wheel controller. It adds
// the processing timer and the "recipe applied" flag to a [SmartInventory], notifies when an
// item was inserted into the working slot, and never gives items back through the handler
// (Java's `ProcessingInventory` overrides `extract` to return nothing).
import '../common/stack.dart';
import '../common/storage.dart';

class ProcessingInventory extends SmartInventory {
  /// 32 slots like the Java inventory; slot 0 is the input, the results go into 1..n.
  static const int size = 32;

  /// `ProcessingInventory.callback`: called with the new contents of slot 0 after an insertion.
  final void Function(PStack stack)? onInserted;

  /// `remainingTime` / `recipeDuration`: the timer of the current item, in ticks.
  double remainingTime = 0;
  double recipeDuration = 0;

  /// `appliedRecipe`: the results are in the inventory, only the timer has to run out.
  bool appliedRecipe = false;

  ProcessingInventory({this.onInserted}) : super(size);

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    final rest = super.insert(slot, stack, simulate: simulate);
    if (!simulate && rest.count < stack.count) onInserted?.call(stackIn(slot));
    return rest;
  }

  /// `extract` returns nothing: only the controller ejects items.
  @override
  PStack extract(int slot, int amount, {bool simulate = false}) => PStack.empty;

  /// `clear()` also drops the timer and the applied flag.
  @override
  void clear() {
    super.clear();
    remainingTime = 0;
    recipeDuration = 0;
    appliedRecipe = false;
  }
}
