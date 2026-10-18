import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// Moving items into and out of the containers of blocks, seen from one side
/// (`item-handler.wit`), like a hopper does.
///
/// ```dart
/// final handler = ItemHandlers.at(world, pos, side: BlockDirection.up);
/// if (handler != null) {
///   final left = await handler.insertStack(stack);   // null: all went in
///   final out = handler.take(0, 8);                  // up to 8 from slot 0
/// }
/// ```
///
/// A handler keeps working after the block is gone, on a container nobody can
/// reach any more: ask for a new one when the block may have changed. It is an
/// owned resource (valid until the callback returns, or `keep()` it).
abstract final class ItemHandlers {
  /// The handler of the container at [pos] seen from [side] (the face of the
  /// block the items go through; `null` sees every slot), or `null` when the
  /// chunk is not loaded or the block has no container.
  static ItemHandler? at(World world, BlockPos pos, {BlockDirection? side}) =>
      generated.itemHandler.getItemHandler(targetWorld: world, pos: pos, side: side);
}

/// Plugin inventories of plugin block entities.
abstract final class PluginInventories {
  /// Gives the plugin block entity at [pos] an inventory of [slotCount] slots
  /// (at most 4096) holding [slotLimit] items each (1 to 99), or resizes it.
  /// Hoppers and [ItemHandlers.at] see it. Throws a [HostException] if there is
  /// no plugin block entity or a slot that would go is not empty.
  static void register(World world, BlockPos pos, {required int slotCount, int slotLimit = 64}) =>
      unwrapHost(
        generated.itemHandler.registerPluginInventory(
          targetWorld: world,
          pos: pos,
          slotCount: slotCount,
          slotLimit: slotLimit,
        ),
        'Registering the inventory at (${pos.x}, ${pos.y}, ${pos.z})',
      );

  /// Takes the inventory away and returns the items that were in it. Throws a
  /// [HostException] if there is no such entity.
  static List<ItemStack> unregister(World world, BlockPos pos) => unwrapHost(
    generated.itemHandler.unregisterPluginInventory(targetWorld: world, pos: pos),
    'Unregistering the inventory at (${pos.x}, ${pos.y}, ${pos.z})',
  );
}

/// Conveniences for [ItemHandler].
extension ItemHandlerApi on ItemHandler {
  /// The stacks of all slots (`null` for empty ones). Each stack is a copy.
  List<ItemStack?> get stacks => [
    for (var slot = 0; slot < slotCount(); slot++) getStack(slot: slot),
  ];

  /// Puts [stack] into the slots in order. Returns what did not fit, `null` if
  /// everything went in. With [simulate] nothing changes. [stack] is not
  /// changed.
  Future<ItemStack?> insertStack(ItemStack stack, {bool simulate = false}) =>
      insert(slot: null, stack: stack, simulate: simulate);

  /// Puts [stack] into [slot] only; see [insertStack].
  Future<ItemStack?> insertInto(int slot, ItemStack stack, {bool simulate = false}) =>
      insert(slot: slot, stack: stack, simulate: simulate);

  /// Whether all of [stack] fits (nothing changes).
  Future<bool> canInsert(ItemStack stack) async =>
      await insertStack(stack, simulate: true) == null;

  /// Takes up to [amount] (at most 255) items out of [slot] as far as this side
  /// may take them, or `null` if there are none.
  ItemStack? take(int slot, int amount, {bool simulate = false}) =>
      extract(slot: slot, amount: amount.clamp(0, 255), simulate: simulate);

  /// Takes up to [amount] items from the first slot that gives any.
  ItemStack? takeFirst(int amount, {bool simulate = false}) {
    for (var slot = 0; slot < slotCount(); slot++) {
      final taken = take(slot, amount, simulate: simulate);
      if (taken != null) return taken;
    }
    return null;
  }
}
