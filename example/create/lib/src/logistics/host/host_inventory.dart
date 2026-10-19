// The item inventories the logistics blocks reach (`Capabilities.ItemHandler.BLOCK`): the host's
// containers as [HostInv], and the plugin's own block entities as [PluginInv] / [StorageInv].
// The host only knows vanilla containers, so a packager, a frogport or an item hatch facing a
// vault, a depot, a basin or a crafter has to ask the plugin first — the same order
// `StorageLookup` uses for the machines.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../conveyance/items/inventory.dart' show ItemInventory;
import '../../conveyance/items/item_codec.dart';
import '../../conveyance/items/item_data.dart';
import '../../conveyance/items/stack_bridge.dart' show fromPStack, toPStack;
import '../../conveyance/transport/transport_inventory_api.dart'
    show ItemInventoryProvider;
import '../../processing/common/capabilities.dart' show ItemStorageProvider;
import '../../processing/common/stack.dart' show PStack;
import '../../processing/common/storage.dart' show ItemStorage;
import '../model/inventory.dart';
import '../model/stack.dart';
import 'runtime.dart' show Lg;
import 'stack_io.dart';

/// An [ItemHandler] of the host (one side of a container) seen as an [ItemInv].
final class HostInv implements ItemInv, StackedInserter {
  final ItemHandler handler;
  final StackIo io;

  HostInv(this.handler, this.io);

  @override
  int get slots => handler.slotCount();

  @override
  Future<LStack> stackAt(int slot) => io.read(handler.getStack(slot: slot));

  @override
  Future<int> slotLimit(int slot) async => handler.getSlotLimit(slot: slot);

  @override
  Future<bool> isValid(int slot, LStack stack) async {
    final hs = await io.write(stack);
    if (hs == null) return false;
    return handler.isItemValid(slot: slot, stack: hs);
  }

  @override
  Future<LStack> extract(int slot, int amount, {bool simulate = false}) async {
    if (amount <= 0) return LStack.empty;
    final taken = handler.extract(slot: slot, amount: amount.clamp(0, 255), simulate: simulate);
    return io.read(taken);
  }

  @override
  Future<LStack> insert(int slot, LStack stack, {bool simulate = false}) async {
    final hs = await io.write(stack);
    if (hs == null) return LStack.empty;
    final rest = await handler.insert(slot: slot, stack: hs, simulate: simulate);
    return io.read(rest);
  }

  @override
  Future<LStack> insertAnywhere(LStack stack, {bool simulate = false}) async {
    final hs = await io.write(stack);
    if (hs == null) return LStack.empty;
    final rest = await handler.insert(slot: null, stack: hs, simulate: simulate);
    return io.read(rest);
  }
}

/// A plugin block entity's inventory (`ItemInventoryProvider`: vault, depot, creative crate,
/// chute, belt, ...) seen as an [ItemInv]. Stacks cross the host form, so the components keep
/// their meaning exactly as they would through a vanilla container.
final class PluginInv implements ItemInv, StackedInserter {
  final ItemInventory inv;
  final StackIo io;

  PluginInv(this.inv, this.io);

  Future<LStack> _read(ItemValue value) async =>
      io.read(await ItemCodec.write(value));

  Future<ItemValue> _write(LStack stack) async =>
      ItemCodec.read(await io.write(stack));

  @override
  int get slots => inv.slots;

  @override
  Future<LStack> stackAt(int slot) async => _read(await inv.getStack(slot));

  @override
  Future<int> slotLimit(int slot) async => await inv.slotLimit(slot);

  @override
  Future<bool> isValid(int slot, LStack stack) async =>
      await inv.isItemValid(slot, await _write(stack));

  @override
  Future<LStack> extract(int slot, int amount, {bool simulate = false}) async =>
      _read(await inv.extract(slot, amount, simulate: simulate));

  @override
  Future<LStack> insert(int slot, LStack stack, {bool simulate = false}) async =>
      _read(await inv.insert(slot, await _write(stack), simulate: simulate));

  /// `TransferUtil.insertItemStacked`: the slots that already hold the item first, then the
  /// empty ones. Done in the plugin's own value type, without a round trip per slot.
  @override
  Future<LStack> insertAnywhere(LStack stack, {bool simulate = false}) async {
    if (stack.isEmpty) return stack;
    var rest = await _write(stack);
    for (var pass = 0; pass < 2 && rest.isNotEmpty; pass++) {
      for (var slot = 0; slot < inv.slots && rest.isNotEmpty; slot++) {
        final present = await inv.getStack(slot);
        if (pass == 0 ? present.isEmpty : present.isNotEmpty) continue;
        rest = await inv.insert(slot, rest, simulate: simulate);
      }
    }
    return _read(rest);
  }
}

/// A plugin machine's storage (`ItemStorageProvider`: basin, crafter, deployer, millstone, ...)
/// seen as an [ItemInv].
final class StorageInv implements ItemInv {
  final ItemStorage storage;
  final StackIo io;

  StorageInv(this.storage, this.io);

  Future<LStack> _read(PStack stack) async =>
      io.read(await ItemCodec.write(fromPStack(stack)));

  Future<PStack> _write(LStack stack) async =>
      toPStack(await ItemCodec.read(await io.write(stack)));

  @override
  int get slots => storage.slots;

  @override
  Future<LStack> stackAt(int slot) async => _read(storage.stackIn(slot));

  @override
  Future<int> slotLimit(int slot) async => storage.slotLimit(slot);

  @override
  Future<bool> isValid(int slot, LStack stack) async =>
      storage.isItemValid(slot, await _write(stack));

  @override
  Future<LStack> extract(int slot, int amount, {bool simulate = false}) async =>
      _read(storage.extract(slot, amount, simulate: simulate));

  @override
  Future<LStack> insert(int slot, LStack stack, {bool simulate = false}) async =>
      _read(storage.insert(slot, await _write(stack), simulate: simulate));
}

/// The item inventory at [pos] seen from [side] (`Capabilities.ItemHandler.BLOCK`): the plugin's
/// own block entities first (the host only knows vanilla containers), then the host's.
ItemInv? inventoryAt(String worldId, Pos pos, StackIo io, {Direction? side}) {
  final be = Lg.i.store.at(worldId, pos.toBlockPos());
  if (be is ItemInventoryProvider) {
    final inv = (be as ItemInventoryProvider).itemInventory(side);
    if (inv != null) return PluginInv(inv, io);
  }
  if (be is ItemStorageProvider) {
    final storage = (be as ItemStorageProvider).itemStorage(side?.name);
    if (storage != null) return StorageInv(storage, io);
  }
  final world = Lg.i.world(worldId);
  if (world == null) return null;
  final h = ItemHandlers.at(world, pos.toBlockPos(), side: side?.toHost());
  return h == null ? null : HostInv(h, io);
}
