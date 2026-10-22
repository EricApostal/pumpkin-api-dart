// The item containers the smart observer and the threshold switch read at the block they
// face: Java's `InvManipulationBehaviour` asks for the `Capabilities.ItemHandler.BLOCK` of that
// block (`bypassSidedness`, so every slot), which in this port is answered by three lookups — the
// plugin inventories of this plugin (a vault, a belt, a depot, ...), the plugin machines' storage
// (a basin, a millstone, a crafter, ...) and the host's `ItemHandlers` for its own containers
// (chest, barrel, hopper, ...). The host lookup needs the host bindings, so it and its adapter
// live in `observer_blocks.dart`; the plugin ones and everything the observer and the switch do
// with a slot are pure and live here.
import 'dart:async';

import '../../conveyance/items/inventory.dart';
import '../../conveyance/items/item_data.dart';
import '../../conveyance/items/stack_bridge.dart' show fromPStack;
import '../../processing/common/storage.dart' show ItemStorage;

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

/// A plugin machine's item storage (`ItemStorage`: a basin, a millstone, a crafter, ...) as an
/// [ObservedContainer]. The machines register `Capabilities.ItemHandler.BLOCK` in Java (a basin
/// registers `CombinedItemHandler(input, output)`, 18 slots); in this port they answer with an
/// [ItemStorage], which the host's `ItemHandlers` does not see.
final class MachineStorageContainer implements ObservedContainer {
  final ItemStorage storage;

  const MachineStorageContainer(this.storage);

  @override
  int get slots => storage.slots;

  @override
  Future<ObservedSlot> slot(int index, {bool detail = false}) async {
    final stack = storage.stackIn(index);
    if (stack.isEmpty) {
      return ObservedSlot(
        key: airKey,
        count: 0,
        limit: detail ? storage.slotLimit(index) : 64,
      );
    }
    // A machine's storage keeps the components of its stacks and not their rendered name: like a
    // plugin inventory it reports none.
    final address = detail ? packageAddressOf(fromPStack(stack)) : '';
    return ObservedSlot(
      key: stack.key,
      count: stack.count,
      limit: detail ? storage.slotLimit(index) : 64,
      maxStack: detail ? stack.maxStack : 64,
      address: address.isEmpty ? null : address,
    );
  }
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