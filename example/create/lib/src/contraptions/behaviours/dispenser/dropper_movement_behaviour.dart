// `DropperMovementBehaviour`: a dropper on a contraption drops one of its items whenever the
// contraption moves it into a new block.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../core/movement.dart';
import '../../storage/mounted_storage.dart';
import '../../storage/stacks.dart';
import '../../actors/actor_runtime.dart';
import 'mounted_dispense_behaviour.dart';

/// `DropperMovementBehaviour`.
class DropperMovementBehaviour extends MovementBehaviour {
  const DropperMovementBehaviour();

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;

    final storage = context.itemStorage;
    if (storage == null) return;

    final slot = _getSlot(storage, context.contraption.storage.allItems);
    if (slot == -1) {
      // all slots empty
      world.playCustomSound(
        soundName: 'minecraft:block.dispenser.fail',
        category: SoundCategory.blocks,
        pos: pos.center,
        volume: 1,
        pitch: 1,
      );
      return;
    }

    // A copy, because the behaviour modifies the stack it gets.
    final stack = storage.stackInSlot(slot);
    final behaviour = getDispenseBehaviour(context, pos, stack);
    final remainder = await behaviour.dispense(stack, context, pos);
    storage.setStackInSlot(slot, remainder);
  }

  /// `getDispenseBehavior`.
  MountedDispenseBehaviour getDispenseBehaviour(
    MovementContext context,
    Pos pos,
    StoredStack stack,
  ) => DefaultMountedDispenseBehaviour.instance;

  /// `getSlot`: a dispensable slot. Empty slots are skipped and nearly-empty slots are topped off
  /// from the contraption inventory.
  static int _getSlot(
    MountedItemStorage storage,
    ItemSlots contraptionInventory,
  ) {
    final filled = <int>[];
    for (var i = 0; i < storage.slots; i++) {
      var stack = storage.stackInSlot(i);
      if (stack.isEmpty) continue;
      if (stack.count == 1 && stack.maxStackSize != 1) {
        final topped = _tryTopOff(stack, contraptionInventory);
        if (topped == null) continue;
        storage.setStackInSlot(i, topped);
        stack = topped;
      }
      filled.add(i);
    }
    return switch (filled.length) {
      0 => -1,
      1 => filled.first,
      _ => filled[actorRandom.nextInt(filled.length)],
    };
  }

  /// `tryTopOff`: fills a single item up from the contraption's inventory.
  static StoredStack? _tryTopOff(StoredStack stack, ItemSlots from) {
    final needed = stack.maxStackSize - stack.count;
    if (needed <= 0) return null;
    final extracted = ItemSlotsHelper.extract(
      from,
      stack.sameItemSameComponents,
      needed,
    );
    return extracted.isEmpty
        ? null
        : stack.copyWithCount(stack.count + extracted.count);
  }
}
