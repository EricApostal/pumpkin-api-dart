// The item containers the smart observer and the threshold switch read at the block they
// face: Java's `InvManipulationBehaviour` asks for the `Capabilities.ItemHandler.BLOCK` of that
// block (`bypassSidedness`, so every slot), which in this port is answered by two lookups — the
// host's `ItemHandlers` for its own containers (chest, barrel, hopper, ...) and the plugin
// inventories of this plugin (a vault, a belt, a depot, ...). The host lookup needs the host
// bindings, so it and its adapter live in `observer_blocks.dart`; the plugin one and everything
// the observer and the switch do with a slot are pure and live here.
import 'dart:async';

import '../../conveyance/items/inventory.dart';
import '../../conveyance/items/item_data.dart';

/// One slot of an observed container: what it holds, and — read only when asked for — the space
/// it gives and the display data of its stack.
final class ObservedSlot {
  /// `getRegistryKey` of the stack, `minecraft:air` when the slot is empty.
  final String key;

  /// `getCount()`.
  final int count;

  /// `getSlotLimit(slot)`: the space the slot gives. Only with `detail`.
  final int limit;

  /// `getMaxStackSize()` of the item in the slot. Only with `detail`.
  final int maxStack;

  /// `getHoverName()` of a stack that carries a custom name, else `null` (the display falls back
  /// to the name of the item). A plugin inventory keeps the components of its stacks, not their
  /// rendered name, and reports none. Only with `detail`.
  final String? name;

  /// `PackageItem.getAddress(stack)`, `null` when the stack is not a package. Only with `detail`;
  /// a host stack keeps the address in a component, read by its adapter.
  final String? address;

  const ObservedSlot({
    required this.key,
    required this.count,
    this.limit = 64,
    this.maxStack = 64,
    this.name,
    this.address,
  });

  bool get isEmpty => count <= 0 || key == airKey;
}

/// The item container at a position, seen from every side (`Capabilities.ItemHandler.BLOCK` read
/// by `InvManipulationBehaviour.bypassSidedness`): a plugin inventory of this plugin, or a
/// container of the host.
abstract interface class ObservedContainer {
  /// `getSlots()`.
  int get slots;

  /// `getStackInSlot(index)`. The key and the count are what the observer's version and match
  /// scans read every tick; `detail` adds `getSlotLimit`, `getMaxStackSize`, `getHoverName` and
  /// the package address, which the display and the threshold switch need and the scans do not.
  Future<ObservedSlot> slot(int index, {bool detail = false});
}

/// A plugin inventory (`ItemInventory`: a vault, a belt, a depot, ...) as an
/// [ObservedContainer].
final class PluginInventoryContainer implements ObservedContainer {
  final ItemInventory inventory;

  const PluginInventoryContainer(this.inventory);

  @override
  int get slots => inventory.slots;

  @override
  Future<ObservedSlot> slot(int index, {bool detail = false}) async {
    final value = await inventory.getStack(index);
    if (!detail) return ObservedSlot(key: value.isEmpty ? airKey : value.key, count: value.count);
    final address = value.isEmpty ? '' : packageAddressOf(value);
    return ObservedSlot(
      key: value.isEmpty ? airKey : value.key,
      count: value.count,
      limit: await inventory.slotLimit(index),
      maxStack: value.maxStack,
      address: address.isEmpty ? null : address,
    );
  }
}