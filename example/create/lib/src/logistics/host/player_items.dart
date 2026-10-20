// Giving item stacks back to a player (`Inventory.placeItemBackInInventory`) and taking them
// out of the inventory. The host inventory has no "insert stacked", so this fills matching
// stacks first, then empty slots, and drops what does not fit.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../model/stack.dart';
import '../requester/auto_request_data.dart';
import 'runtime.dart';

/// The generic 36 slot inventory of [player], with the owned [PlayerInventory] handle released.
Inventory playerInventory(Player player) {
  final inventory = player.getInventory();
  final generic = inventory.asInventory();
  inventory.dispose();
  return generic;
}

/// `player.getInventory().placeItemBackInInventory(stack)`.
Future<void> giveToPlayer(Player player, LStack stack) async {
  if (stack.isEmpty) return;
  final host = await Lg.i.write(stack);
  if (host == null) return;
  final inv = playerInventory(player);
  try {
    var remaining = await host.getCount();
    final max = await host.getMaxCount();
    final key = await host.getRegistryKey();

    // Fill stacks of the same item first.
    for (var slot = 0; slot < inv.getSize() && remaining > 0; slot++) {
      final existing = inv.getItem(slot: slot);
      if (existing == null) continue;
      if (await existing.getRegistryKey() != key) continue;
      final count = await existing.getCount();
      if (count >= max) continue;
      final add = remaining < max - count ? remaining : max - count;
      await existing.setCount(count: count + add);
      await inv.setItem(slot: slot, item: existing);
      remaining -= add;
    }

    // Then empty slots.
    for (var slot = 0; slot < inv.getSize() && remaining > 0; slot++) {
      if (inv.getItem(slot: slot) != null) continue;
      final add = remaining < max ? remaining : max;
      final copy = ItemStack.create(registryKey: key, count: add);
      await inv.setItem(slot: slot, item: copy);
      remaining -= add;
    }

    if (remaining <= 0) return;
    final world = player.getWorld();
    try {
      final pos = player.getPosition();
      final drop = ItemStack.create(registryKey: key, count: remaining);
      await world.dropItem(pos, drop);
    } finally {
      world.dispose();
    }
  } finally {
    inv.dispose();
  }
}

/// Takes one item out of the hand [hand] of [player].
Future<void> consumeOneInHand(Player player, Hand hand) async {
  final inventory = player.getInventory();
  try {
    final stack = inventory.getItemInHand(hand: hand);
    if (stack == null) return;
    final count = await stack.getCount();
    if (count <= 1) {
      await inventory.setItemInHand(hand: hand, item: null);
    } else {
      await stack.setCount(count: count - 1);
      await inventory.setItemInHand(hand: hand, item: stack);
    }
  } finally {
    inventory.dispose();
  }
}

/// The `create:auto_request_data` component of the item in the hands of [player]
/// (`AutoRequestData.readFromItem`'s stack): a redstone requester or a table cloth programmed at a
/// stock keeper carries the order and the address of the keeper.
Future<AutoRequestData?> heldRequestData(Player player) async {
  final inventory = player.getInventory();
  try {
    for (final hand in [Hand.right, Hand.left]) {
      final held = inventory.getItemInHand(hand: hand);
      if (held == null) continue;
      final stack = await Lg.i.read(held);
      final bytes = stack.compBytes('create:auto_request_data');
      if (bytes == null) continue;
      return AutoRequestData.decode(bytes, Lg.i.wire);
    }
  } finally {
    inventory.dispose();
  }
  return null;
}
