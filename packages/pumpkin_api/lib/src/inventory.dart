import 'dart:async';

import 'bindings.g.dart';
import 'blocks.dart';

/// Conveniences for [Inventory].
///
/// Items put into an inventory are consumed: don't use an [ItemStack] again
/// after passing it to `[]=`, [give], [items] or `setItem`.
extension InventoryHelpers on Inventory {
  /// Whether at least one slot has an item.
  bool get isNotEmpty => !isEmpty();

  /// The item in [slot], or `null` if it is empty.
  ItemStack? operator [](int slot) => getItem(slot: slot);

  /// Puts [item] in [slot], or empties the slot when `null`. [item] is
  /// consumed. The host applies it right after, use `setItem` to wait for it.
  void operator []=(int slot, ItemStack? item) =>
      unawaited(setItem(slot: slot, item: item));

  /// All slots, with `null` for the empty ones.
  List<ItemStack?> get items => getAllItems();

  /// Replaces every slot. Items are consumed. The host applies it right after,
  /// use `setAllItems` to wait for it.
  set items(List<ItemStack?> value) => unawaited(setAllItems(items: value));

  /// Removes and returns the item in [slot], or `null` if it was empty.
  Future<ItemStack?> take(int slot) => removeItem(slot: slot);

  /// The number of items of the kind [key] (`diamond` or `minecraft:diamond`)
  /// in this inventory, counted over all stacks.
  int count(String key) => countItem(itemId: normalizeRegistryKey(key));

  /// Whether the inventory holds at least one item of the kind [key].
  bool contains(String key) => containsItem(itemId: normalizeRegistryKey(key));

  /// The index of the first empty slot, or -1 if the inventory is full.
  int get firstEmptySlot {
    final all = getAllItems();
    for (var i = 0; i < all.length; i++) {
      if (all[i] == null) return i;
    }
    return -1;
  }

  /// Puts [item] in the first empty slot and returns `true`, or returns
  /// `false` when the inventory is full. [item] is consumed only when it is
  /// placed. This doesn't merge with existing stacks.
  Future<bool> give(ItemStack item) async {
    final slot = firstEmptySlot;
    if (slot < 0) return false;
    await setItem(slot: slot, item: item);
    return true;
  }
}

/// Conveniences for [PlayerInventory]. The slots (`helmet`, `chestplate`,
/// `leggings`, `boots`, `offHand`, `selectedSlot`) are properties of the
/// inventory itself.
///
/// Items assigned to a setter are consumed.
extension PlayerInventoryHelpers on PlayerInventory {
  /// The 36 hotbar and storage slots.
  Inventory get storage => asInventory();

  /// The item in the selected hotbar slot, or `null`.
  ItemStack? get heldItem => storage[selectedSlot];

  set heldItem(ItemStack? item) => storage[selectedSlot] = item;

  /// The item in [hand], or `null`.
  ItemStack? itemIn(Hand hand) => getItemInHand(hand: hand);
}
