// What the item-transport blocks offer each other and the rest of the plugin (pure): a plugin
// block entity that owns an inventory reachable from the outside, plus the conversion between the
// conveyance `ItemValue` and the processing `PStack` used by the machines above a depot.
//
// The host-side lookup (plugin inventories first, then vanilla containers through
// `ItemHandlers`) lives in `transport_inventory.dart`, which imports the host bindings.
import '../../common/direction.dart';
import '../../processing/common/stack.dart';
import '../items/inventory.dart';
import '../items/item_data.dart';
import '../items/stack_bridge.dart';

export '../../processing/common/stack.dart' show PStack;

/// A plugin block entity that owns an item inventory reachable from the outside, the plugin-side
/// equivalent of `Capabilities.ItemHandler.BLOCK` (`StorageLookup.pluginItemStorage`). Funnels,
/// chutes, tunnels and depots look for it before asking the host for a vanilla container.
abstract interface class ItemInventoryProvider {
  /// The inventory seen from [side] (`null` = from inside / any side), or `null` when the block
  /// has none there.
  ItemInventory? itemInventory(Direction? side);
}

/// `PStack` of an [ItemValue] (the machines' item type).
PStack pStackOf(ItemValue stack) => toPStack(stack);

/// [ItemValue] of a `PStack`.
ItemValue itemValueOf(PStack stack) => fromPStack(stack);
