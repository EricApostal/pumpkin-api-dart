// Player inventory helpers: `Inventory.placeItemBackInInventory`, held item access.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

/// `Inventory.placeItemBackInInventory(stack)`: merges into matching stacks, then empty
/// slots, drops what is left at the player. The stack is consumed.
Future<void> giveToPlayer(Player player, World world, ItemStack stack) async {
  var remaining = await stack.getCount();
  if (remaining <= 0) return;
  final key = await stack.getRegistryKey();
  final storage = player.getInventory().asInventory();
  final max = await stack.getMaxCount();
  final size = storage.getSize();
  if (max > 1) {
    for (var i = 0; i < size && remaining > 0; i++) {
      final slot = storage.getItem(slot: i);
      if (slot == null) continue;
      if (await slot.getRegistryKey() != key) continue;
      final count = await slot.getCount();
      if (count >= max) continue;
      final room = max - count;
      final moved = remaining < room ? remaining : room;
      await slot.setCount(count: count + moved);
      remaining -= moved;
    }
  }
  if (remaining > 0) {
    for (var i = 0; i < size && remaining > 0; i++) {
      if (storage.getItem(slot: i) != null) continue;
      if (remaining == await stack.getCount()) {
        await storage.setItem(slot: i, item: stack);
        return;
      }
      await stack.setCount(count: remaining);
      await storage.setItem(slot: i, item: stack);
      return;
    }
  }
  if (remaining > 0) {
    await stack.setCount(count: remaining);
    final pos = player.getPosition();
    await world.dropItem(pos, stack);
  }
}

/// The stack in [hand], or `null`.
ItemStack? heldStack(Player player, Hand hand) => player.getInventory().getItemInHand(hand: hand);

/// Takes one item of the stack in a slot (`ItemStack.shrink(1)` + remove if empty).
Future<void> shrinkSlot(Inventory inv, int slot, int amount) async {
  final stack = inv.getItem(slot: slot);
  if (stack == null) return;
  final count = await stack.getCount();
  if (count - amount <= 0) {
    await inv.setItem(slot: slot, item: null);
  } else {
    await stack.setCount(count: count - amount);
    await inv.setItem(slot: slot, item: stack);
  }
}

/// Shrinks the held stack of [hand] by [amount].
Future<void> shrinkHeld(Player player, Hand hand, int amount) async {
  final inv = player.getInventory();
  final stack = inv.getItemInHand(hand: hand);
  if (stack == null) return;
  final count = await stack.getCount();
  if (count - amount <= 0) {
    await inv.setItemInHand(hand: hand, item: null);
  } else {
    await stack.setCount(count: count - amount);
    await inv.setItemInHand(hand: hand, item: stack);
  }
}

/// `ItemStack.hurtAndBreak(amount, ...)` for a damageable item: adds to the damage, removes
/// the stack when it breaks. Uses the `minecraft:damage` / `max_damage` components.
Future<void> hurtHeld(Player player, Hand hand, int amount) async {
  final inv = player.getInventory();
  final stack = inv.getItemInHand(hand: hand);
  if (stack == null) return;
  if (await damageStack(stack, amount)) {
    await inv.setItemInHand(hand: hand, item: null);
  } else {
    await inv.setItemInHand(hand: hand, item: stack);
  }
}

/// Adds [amount] damage to [stack]. Returns true when the stack is used up (broke).
Future<bool> damageStack(ItemStack stack, int amount) async {
  final comps = await stack.getComponents();
  var damage = 0;
  var maxDamage = 0;
  for (final c in comps) {
    if (c.component == DataComponent.damage) {
      damage = _varInt(c.value);
    } else if (c.component == DataComponent.maxDamage) {
      maxDamage = _varInt(c.value);
    }
  }
  if (maxDamage <= 0) return false;
  damage += amount;
  if (damage >= maxDamage) return true;
  await stack.setComponent(component: DataComponent.damage, value: _writeVarInt(damage));
  return false;
}

int _varInt(List<int> bytes) {
  var value = 0;
  var shift = 0;
  for (final b in bytes) {
    value |= (b & 0x7F) << shift;
    if (b & 0x80 == 0) break;
    shift += 7;
  }
  return value;
}

List<int> _writeVarInt(int v) {
  final out = <int>[];
  var value = v;
  do {
    var b = value & 0x7F;
    value >>= 7;
    if (value != 0) b |= 0x80;
    out.add(b);
  } while (value != 0);
  return out;
}
