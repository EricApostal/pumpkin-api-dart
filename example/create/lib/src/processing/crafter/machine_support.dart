// Small host helpers shared by the crafter, deployer and arm parts (the three machine families of
// this porting task): block state conversion, wrench detection, giving stacks to a player and
// dropping them into the world. Kept in one file so the three parts do not repeat them.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';

/// The server's recipe manager, kept by the crafter part while the server runs. The mechanical
/// crafter matches vanilla crafting recipes through it (`RecipeGridHandler.tryToApplyRecipe`).
RecipeManager? sharedCraftingRecipes;

/// The pure [BState] of a kinetic block state.
BState bStateOf(KState state) => BState(state.block, Map.of(state.props));

/// Whether [itemKey] is a wrench (`AllItems.WRENCH` or the `c:tools/wrench` tag).
bool isWrenchItem(ProcessingRuntime rt, String itemKey) =>
    itemKey == 'create:wrench' || rt.tags.itemHasTag(itemKey, 'c:tools/wrench');

/// `ItemHelper.dropContents` / `Player.drop`: gives [stack] to [player], merging with equal
/// stacks first, then filling empty slots; whatever does not fit is dropped at the player.
Future<void> giveToPlayerStack(Player player, World world, PStack stack) async {
  var rest = stack;
  if (rest.isEmpty) return;

  final inventory = player.getInventory().storage;
  final size = inventory.getSize();

  for (var slot = 0; slot < size && rest.isNotEmpty; slot++) {
    final existing = inventory.getItem(slot: slot);
    if (existing == null) continue;
    final value = await HostStacks.read(existing);
    existing.dispose();
    if (!value.sameItemSameComponents(rest)) continue;
    final space = rest.maxStack - value.count;
    if (space <= 0) continue;
    final moved = math.min(space, rest.count);
    final merged = value.withCount(value.count + moved);
    final out = await HostStacks.write(merged);
    if (out != null) await inventory.setItem(slot: slot, item: out);
    rest = rest.withCount(rest.count - moved);
  }

  for (var slot = 0; slot < size && rest.isNotEmpty; slot++) {
    final existing = inventory.getItem(slot: slot);
    if (existing != null) {
      existing.dispose();
      continue;
    }
    final out = await HostStacks.write(rest);
    if (out == null) return;
    await inventory.setItem(slot: slot, item: out);
    rest = PStack.empty;
  }

  if (rest.isNotEmpty) {
    await dropPStack(world, player.getPosition(), rest);
  }
}

/// Drops [stack] as an item entity at [pos]; [pickupDelay] ticks of pickup delay.
Future<void> dropPStack(
  World world,
  Vec3 pos,
  PStack stack, {
  int pickupDelay = 10,
}) async {
  if (stack.isEmpty) return;
  final item = await HostStacks.write(stack);
  if (item == null) return;
  try {
    await world.dropItem(pos, item, pickupDelay: pickupDelay);
  } finally {
    item.dispose();
  }
}

/// Takes [amount] items out of the main hand of [player] (`stack.shrink`).
Future<void> consumeFromHand(Player player, Hand hand, int amount) async {
  final held = player.getItemInHand(hand: hand);
  if (held == null) return;
  final count = await held.getCount();
  if (count - amount <= 0) {
    held.dispose();
    await player.setItemInHand(hand: hand, stack: null);
    return;
  }
  await held.setCount(count: count - amount);
  await player.setItemInHand(hand: hand, stack: held);
}
