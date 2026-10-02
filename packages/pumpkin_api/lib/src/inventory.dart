import 'package:wasm_components/wasm_components.dart' show Option;

import 'bindings.g.dart';
import 'blocks.dart';

T? _orNull<T>(Option<T> option) => option.hasValue ? option.requireValue() : null;

Option<T> _opt<T>(T? value) => value == null ? Option.none : Option.some(value);

/// Conveniences for [Inventory].
///
/// Items put into an inventory are consumed: don't use an [ItemStack] again
/// after passing it to `[]=`, [give], [items] or `setItem`.
extension InventoryHelpers on Inventory {
  /// The number of slots.
  int get size => getSize();

  /// Whether at least one slot has an item.
  bool get isNotEmpty => !isEmpty();

  /// The item in [slot], or `null` if it is empty.
  ItemStack? operator [](int slot) => _orNull(getItem(slot: slot));

  /// Puts [item] in [slot], or empties the slot when `null`. [item] is
  /// consumed.
  void operator []=(int slot, ItemStack? item) =>
      setItem(slot: slot, item: _opt(item));

  /// All slots, with `null` for the empty ones.
  List<ItemStack?> get items => [
    for (final item in getAllItems()) _orNull(item),
  ];

  /// Replaces every slot. Items are consumed.
  set items(List<ItemStack?> value) =>
      setAllItems(items: [for (final item in value) _opt(item)]);

  /// Removes and returns the item in [slot], or `null` if it was empty.
  ItemStack? take(int slot) => _orNull(removeItem(slot: slot));

  /// The number of items of the kind [key] (`diamond` or `minecraft:diamond`)
  /// in this inventory, counted over all stacks.
  int count(String key) => countItem(itemId: normalizeRegistryKey(key));

  /// Whether the inventory holds at least one item of the kind [key].
  bool contains(String key) => containsItem(itemId: normalizeRegistryKey(key));

  /// The index of the first empty slot, or -1 if the inventory is full.
  int get firstEmptySlot {
    final all = getAllItems();
    for (var i = 0; i < all.length; i++) {
      if (!all[i].hasValue) return i;
    }
    return -1;
  }

  /// Puts [item] in the first empty slot and returns `true`, or returns
  /// `false` when the inventory is full. [item] is consumed only when it is
  /// placed. This doesn't merge with existing stacks.
  bool give(ItemStack item) {
    final slot = firstEmptySlot;
    if (slot < 0) return false;
    this[slot] = item;
    return true;
  }
}

/// Conveniences for [PlayerInventory].
///
/// Items assigned to a setter are consumed.
extension PlayerInventoryHelpers on PlayerInventory {
  /// The 36 hotbar and storage slots.
  Inventory get storage => asInventory();

  /// The selected hotbar slot, 0 to 8.
  int get selectedSlot => getSelectedSlot();

  set selectedSlot(int slot) => setSelectedSlot(slot: slot);

  /// The item in the selected hotbar slot, or `null`.
  ItemStack? get heldItem => storage[selectedSlot];

  set heldItem(ItemStack? item) => storage[selectedSlot] = item;

  /// The worn helmet, or `null`.
  ItemStack? get helmet => _orNull(getHelmet());

  set helmet(ItemStack? item) => setHelmet(item: _opt(item));

  /// The worn chestplate, or `null`.
  ItemStack? get chestplate => _orNull(getChestplate());

  set chestplate(ItemStack? item) => setChestplate(item: _opt(item));

  /// The worn leggings, or `null`.
  ItemStack? get leggings => _orNull(getLeggings());

  set leggings(ItemStack? item) => setLeggings(item: _opt(item));

  /// The worn boots, or `null`.
  ItemStack? get boots => _orNull(getBoots());

  set boots(ItemStack? item) => setBoots(item: _opt(item));

  /// The item in the off hand, or `null`.
  ItemStack? get offHand => _orNull(getOffHand());

  set offHand(ItemStack? item) => setOffHand(item: _opt(item));

  /// The item in [hand], or `null`.
  ItemStack? itemIn(Hand hand) => _orNull(getItemInHand(hand: hand));
}
