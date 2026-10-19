// Finding and driving item inventories next to the item-transport blocks (host side): the plugin
// inventories of other blocks of this plugin first ([ItemInventoryProvider]), then the host's
// containers (chests, barrels, hoppers, ...) through `ItemHandlers`. Reads and writes stay
// `FutureOr` because host containers can only be reached asynchronously.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../items/inventory.dart';
import '../items/item_codec.dart';
import '../items/item_data.dart';
import '../runtime.dart';
import 'transport_inventory_api.dart';

/// A host `ItemHandler` (one side of a vanilla container) seen as an [ItemInventory].
final class HostItemInventory implements ItemInventory {
  final ItemHandler handler;

  HostItemInventory(this.handler);

  @override
  int get slots => handler.slotCount();

  @override
  FutureOr<ItemValue> getStack(int slot) =>
      ItemCodec.read(handler.getStack(slot: slot));

  @override
  FutureOr<int> slotLimit(int slot) => handler.getSlotLimit(slot: slot);

  @override
  FutureOr<bool> isItemValid(int slot, ItemValue stack) async {
    final hostStack = await ItemCodec.write(stack);
    if (hostStack == null) return false;
    return handler.isItemValid(slot: slot, stack: hostStack);
  }

  @override
  FutureOr<ItemValue> insert(
    int slot,
    ItemValue stack, {
    bool simulate = false,
  }) async {
    if (stack.isEmpty) return ItemValue.empty;
    final hostStack = await ItemCodec.write(stack);
    if (hostStack == null) return ItemValue.empty;
    final rest = await handler.insert(
      slot: slot,
      stack: hostStack,
      simulate: simulate,
    );
    return ItemCodec.read(rest);
  }

  @override
  FutureOr<ItemValue> extract(int slot, int amount, {bool simulate = false}) =>
      ItemCodec.read(
        handler.extract(
          slot: slot,
          amount: amount.clamp(0, 255),
          simulate: simulate,
        ),
      );
}

/// `Capabilities.ItemHandler.BLOCK` lookups for the item-transport blocks.
abstract final class ItemInventories {
  /// The inventory at [pos] of world [worldId] seen from [side], or `null` when the block has
  /// none there.
  static ItemInventory? at(String worldId, Pos pos, {Direction? side}) {
    final rt = ConveyanceRuntime.i;
    final be = rt.store.at(worldId, pos.toBlockPos());
    if (be is ItemInventoryProvider)
      return (be as ItemInventoryProvider).itemInventory(side);
    final world = rt.worldOf(worldId);
    if (world == null) return null;
    final handler = ItemHandlers.at(
      world,
      pos.toBlockPos(),
      side: side?.toHost(),
    );
    return handler == null ? null : HostItemInventory(handler);
  }

  /// Whether the block at [pos] has an item inventory reachable from [side].
  static bool has(String worldId, Pos pos, {Direction? side}) =>
      at(worldId, pos, side: side) != null;
}

/// The item in [hand] of [player] as a value (`minecraft:air` / empty when the hand is empty).
Future<ItemValue> itemInHand(Player player, Hand hand) =>
    ItemCodec.read(player.getItemInHand(hand: hand));

/// `Inventory.placeItemBackInInventory`: gives [stack] to [player], dropping what does not fit.
Future<void> giveToPlayer(Player player, ItemValue stack) =>
    ItemCodec.giveToPlayer(player, stack);
