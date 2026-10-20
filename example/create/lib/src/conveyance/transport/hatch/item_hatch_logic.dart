// `ItemHatchBlock.useItemOn` as plain rules (pure): which inventory slots a click considers,
// which items fit into a container, and the result message. The host side (`item_hatch_block.dart`)
// runs the insertion against the inventory behind the hatch.
import 'package:pumpkin_api/pumpkin_api_core.dart' show PlacementRule;

import '../../items/item_data.dart';

/// `ItemHatchBlock.getStateForPlacement`: the opposite of the clicked face, and **no** placement
/// for a click on a top or bottom face (`return null`).
///
/// The host cannot refuse a placement from a rule and has no source for the clicked face on a
/// four-value property, so the look direction stands in for `clickedFace.getOpposite()`: it is
/// that value whenever the player clicks the face they look at. The vertical-click refusal is
/// missing until the host offers one.
const List<PlacementRule> itemHatchPlacementRules = [
  PlacementRule.horizontalFacing('facing'),
  PlacementRule.inWater('waterlogged'),
];

/// `Inventory.isHotbarSlot`: the nine hotbar slots.
bool isHotbarSlot(int slot) => slot >= 0 && slot < 9;

/// The slot rule of `ItemHatchBlock.useItemOn`:
///
/// * an empty-hand click (`depositItemInHand`) only considers the selected hotbar slot;
/// * a sneaking click considers the main inventory (slots 9..35), not the hotbar.
bool hatchConsidersSlot(
  int slot, {
  required bool depositItemInHand,
  required int selectedSlot,
}) {
  if (isHotbarSlot(slot) != depositItemInHand) return false;
  if (depositItemInHand && slot != selectedSlot) return false;
  return true;
}

/// `Item.canFitInsideContainerItems()`: everything except shulker boxes. `PackageItem` overrides
/// the rule to `true`, so Create's packages always fit.
bool canFitInsideContainerItems(ItemValue stack) =>
    isPackageKey(stack.key) || !isShulkerBox(stack.key);

/// Whether [key] is one of the seventeen shulker boxes.
bool isShulkerBox(String key) =>
    key == 'minecraft:shulker_box' || key.endsWith('_shulker_box');

/// `CreateLang.translate("item_hatch.deposit_item" | "item_hatch.deposit_inventory")`.
String hatchStatusMessage({required bool depositItemInHand}) =>
    depositItemInHand
    ? 'Deposited the held item into the inventory'
    : 'Deposited the inventory into the hatch';
