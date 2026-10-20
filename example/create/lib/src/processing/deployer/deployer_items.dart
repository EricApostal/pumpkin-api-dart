// Pure helpers of the deployer's items: the crafting remainder of an item, whether an item
// stands upright on a belt, and the angle a processed item lands at. No host bindings, so the
// belt callbacks and the tests share them.
import 'dart:math' show Random;

import '../common/stack.dart';
import '../recipe/ingredient.dart' show TagLookup;

/// Crafting remainders of items that a module adds ([craftingRemainderOf] falls back to the
/// vanilla table below). Register an item's remainder here when it has one.
final Map<String, PStack> craftingRemainderOverrides = {};

/// `Item.getCraftingRemainder()`: the stack left behind when one item of [stack] is used up.
///
/// The host exposes no item API for it, so the vanilla items that have one are listed here
/// (`Items` sets them with `Properties.craftRemainder`); [craftingRemainderOverrides] carries
/// the modded ones.
PStack? craftingRemainderOf(PStack stack) {
  if (stack.isEmpty) return null;
  final custom = craftingRemainderOverrides[stack.key];
  if (custom != null) return custom;
  return switch (stack.key) {
    'minecraft:water_bucket' ||
    'minecraft:lava_bucket' ||
    'minecraft:milk_bucket' ||
    'minecraft:powder_snow_bucket' ||
    'minecraft:axolotl_bucket' ||
    'minecraft:cod_bucket' ||
    'minecraft:salmon_bucket' ||
    'minecraft:tropical_fish_bucket' ||
    'minecraft:pufferfish_bucket' ||
    'minecraft:tadpole_bucket' => const PStack('minecraft:bucket', 1),
    'minecraft:honey_bottle' ||
    'minecraft:ominous_bottle' ||
    'minecraft:potion' ||
    'minecraft:splash_potion' ||
    'minecraft:lingering_potion' ||
    'minecraft:dragon_breath' => const PStack('minecraft:glass_bottle', 1),
    'minecraft:mushroom_stew' ||
    'minecraft:rabbit_stew' ||
    'minecraft:beetroot_soup' ||
    'minecraft:suspicious_stew' => const PStack('minecraft:bowl', 1),
    _ => null,
  };
}

/// `heldItem.getItem() instanceof SandPaperItem` (`DeployerBlockEntity.java:604`): the two items
/// of that class, `create:sand_paper` and `create:red_sand_paper` (`AllItems.java:387-395`).
///
/// The items are not named `create:sandpaper`: that is the *tag* that holds them
/// (`AllTags.AllItemTags.SANDPAPER`), so testing the item key against it never matches.
bool isSandPaperItem(PStack stack) =>
    stack.key == 'create:sand_paper' || stack.key == 'create:red_sand_paper';

/// Items that are fluid containers (`TransferUtil.hasFluidHandler`): the buckets.
bool _isFluidHandlerItem(String key) =>
    key == 'minecraft:bucket' ||
    (key.startsWith('minecraft:') &&
        key.endsWith('_bucket') &&
        !key.contains('powder_snow'));

/// `BeltHelper.isItemUpright(stack)`: `(fluid handler || #create:upright_on_belt) &&
/// !#create:not_upright_on_belt`.
bool isItemUprightStack(PStack stack, TagLookup tags) {
  if (stack.isEmpty) return false;
  final key = stack.key;
  final useUpright = tags.itemHasTag(key, 'create:upright_on_belt');
  final forceDisable = tags.itemHasTag(key, 'create:not_upright_on_belt');
  return (_isFluidHandlerItem(key) || useUpright) && !forceDisable;
}

/// The angle a processed item takes on the belt (`BeltDeployerCallbacks.activate`):
/// `BeltHelper.isItemUpright(stack) ? 180 : Create.RANDOM.nextInt(360)`. An item that stands
/// upright is placed centred; anything else lands at a random angle.
int transportedAngleFor(PStack stack, TagLookup tags, Random random) =>
    isItemUprightStack(stack, tags) ? 180 : random.nextInt(360);
