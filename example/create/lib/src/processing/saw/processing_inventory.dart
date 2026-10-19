// `ProcessingInventory` (pure storage): the one input slot of the saw and the press, with the
// processing timer the machine ticks down. `content/processing/recipe/ProcessingInventory.java`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/pos.dart' hide pos;
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';

/// A machine's processing inventory: 32 slots (slot 0 is the input, the rest take the results),
/// with the remaining and total time of the current recipe.
final class ProcessingInventory extends SmartInventory {
  ProcessingInventory({this.limitToOne = false}) : super(32);

  /// `withSlotLimit`: slot 0 holds one item (unless the config allows bulk processing).
  final bool limitToOne;

  /// `remainingTime`: `-1` when the machine waits for an item.
  double remainingTime = -1;

  /// `recipeDuration`.
  double recipeDuration = 0;

  /// `appliedRecipe`.
  bool appliedRecipe = false;

  @override
  int slotLimit(int slot) => limitToOne ? 1 : super.slotLimit(slot);

  /// `isItemValid`: only the empty input slot takes items.
  @override
  bool isItemValid(int slot, PStack stack) => slot == 0 && isEmpty;

  /// The machine never lets its contents be pulled out (`extract` returns nothing).
  @override
  PStack extract(int slot, int amount, {bool simulate = false}) => PStack.empty;

  /// `clear()`: empties the inventory and forgets the running recipe.
  void clearAll() {
    clear();
    remainingTime = 0;
    recipeDuration = 0;
    appliedRecipe = false;
  }

  /// `serializeNBT`: the stacks plus `ProcessingTime`, `RecipeTime`, `AppliedRecipe`.
  NbtCompound writeNbt() => StackNbt.writeList(contents)
    ..putFloat('ProcessingTime', remainingTime)
    ..putFloat('RecipeTime', recipeDuration)
    ..putBool('AppliedRecipe', appliedRecipe);

  /// `deserializeNBT`.
  void readNbt(NbtCompound tag) {
    load(StackNbt.readList(tag, 32));
    remainingTime = tag.getDouble('ProcessingTime') ?? 0;
    recipeDuration = tag.getDouble('RecipeTime') ?? 0;
    appliedRecipe = tag.getBool('AppliedRecipe') ?? false;
    if (isEmpty) appliedRecipe = false;
  }
}

/// `ItemHelper.dropContents`: gives every stack of [storage] to [player] (the rest is dropped at
/// [world] / [pos]).
Future<void> dropContentsToPlayer(
  ItemStorage storage,
  Player player,
  World world,
  Pos pos,
) async {
  final inventory = player.getInventory().storage;
  for (var slot = 0; slot < storage.slots; slot++) {
    final stack = storage.stackIn(slot);
    if (stack.isEmpty) continue;
    final item = await HostStacks.write(stack);
    if (item == null) continue;
    final added = await inventory.give(item);
    if (!added) {
      await world.dropItem(pos.center, item);
    }
  }
}
