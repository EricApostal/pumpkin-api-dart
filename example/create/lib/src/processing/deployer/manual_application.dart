// `ManualApplicationRecipe.manualApplicationRecipesApplyInWorld`
// (`ManualApplicationRecipe.java:49-125`): right-clicking a block with the held item of a
// `create:item_application` recipe transforms the block in place, without a deployer. The
// recipe's first ingredient is tested against the block's item (`testBlock`), the second
// against the held item; the first result becomes the new block (its properties copied over),
// the other results are popped at the position.
//
// Java hooks `PlayerInteractEvent.RightClickBlock`, which fires before the block and the item
// do anything with the click; the host fires `Events.playerUseBlock` at the same point, so the
// port intercepts that and cancels the click when a recipe applies.
import 'dart:async';
import 'dart:math' show Random;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../core/module.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show giveToPlayerStack;
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe.dart';
import 'deployer_items.dart';
import 'manual_application_recipes.dart';

/// The `create:item_application` recipes applied by a right click.
abstract final class ManualApplication {
  /// `onLoad`: intercepts the block clicks of players.
  static void install(CreateContext ctx) {
    ctx.host.intercept(Events.playerUseBlock, _onUse);
  }

  /// The recipe [held] applies to the block whose item form is [blockItem]
  /// (`manualApplicationRecipesApplyInWorld`).
  static ProcessingRecipe? _recipeOf(ProcessingRuntime rt, String blockKey, PStack held) =>
      ManualApplicationRecipes.findRecipe(
        rt.recipes,
        rt.tags,
        PStack(ManualApplicationRecipes.blockItemKey(blockKey), 1),
        held,
      );

  static Future<PlayerUseBlockEventData> _onUse(
    Server server,
    PlayerUseBlockEventData e,
  ) async {
    if (e.cancelled) return e;
    if (!ProcessingRuntime.isLoaded) return e;
    if (e.block == 'minecraft:air' || e.block == 'minecraft:cave_air' || e.block == 'minecraft:void_air') {
      return e;
    }

    final rt = ProcessingRuntime.instance;
    final held = await HostStacks.read(e.item);
    if (held.isEmpty) return e;

    final world = e.player.getWorld();
    final stateId = world.getBlockStateId(pos: e.blockPos);
    final blockKey = BlockStates.blockKey(stateId);
    if (blockKey == null) return e;

    final recipe = _recipeOf(rt, blockKey, held);
    if (recipe == null) return e;

    // `event.setCancellationResult(InteractionResult.SUCCESS); event.setCanceled(true);`
    final random = rt.random;
    final block = ManualApplicationRecipes.transformedBlock(recipe, random);
    final drops = ManualApplicationRecipes.rolledItems(recipe, random, block);

    final pos = e.blockPos.toPos();
    world.playSound(
      sound: Sound.blockCopperBreak,
      category: SoundCategory.players,
      pos: (pos.$1 + .5, pos.$2 + .5, pos.$3 + .5),
      volume: 1,
      pitch: 1.45,
    );

    // `level.destroyBlock(pos, false)`, then the transformed state with `Block.UPDATE_ALL`.
    await world.destroyBlock(
      pos: e.blockPos,
      drop: false,
      player: null,
      withParticles: true,
    );
    if (block != null) {
      final target = BlockStates.defaultOf(block);
      if (target != null) {
        await setBlockState(
          world,
          pos,
          HostBlockGetter.stateOfId(BlockStates.copyProperties(stateId, target)),
        );
      }
    }

    // `recipe.rollResults(level.getRandom()).forEach(stack -> Block.popResource(...))`.
    for (final drop in drops) {
      final stack = await HostStacks.write(drop);
      if (stack == null) continue;
      await world.dropItem(
        (pos.$1 + .5, pos.$2 + .5 + 0.125, pos.$3 + .5),
        stack,
      );
    }

    await _consumeHeld(e, held, recipe, rt);
    await _award(rt, e.player, block);
    return e.cancel();
  }

  /// The held item after the application: `heldItem.hurtAndBreak(1, player, MAINHAND)` for a
  /// damageable item, else its crafting remainder and one item consumed.
  static Future<void> _consumeHeld(
    PlayerUseBlockEventData e,
    PStack held,
    ProcessingRecipe recipe,
    ProcessingRuntime rt,
  ) async {
    // `boolean keepHeld = recipe.shouldKeepHeldItem() || creative;`
    if (recipe.keepHeldItem || e.player.isCreative) return;
    // `boolean unbreakable = heldItem.has(DataComponents.UNBREAKABLE);`
    if (held.hasComponent('minecraft:unbreakable')) return;

    final inventory = e.player.getInventory();
    final maxDamage = _readVarInt(held.component('minecraft:max_damage'));
    if (maxDamage > 0) {
      // `ItemStack.hurtAndBreak`: `minecraft:unbreaking` can negate the point of damage
      // (`EnchantmentHelper.processDurabilityChange`, 1 in level+1).
      var damage = 1;
      final level = await _unbreakingLevel(e.item);
      if (level > 0 && rt.random.nextDouble() < 1 / (level + 1)) damage = 0;
      if (damage <= 0) return;
      final next = _readVarInt(held.component('minecraft:damage')) + damage;
      if (next >= maxDamage) {
        await inventory.setItemInHand(hand: e.hand, item: null);
        return;
      }
      final damaged = held.withComponent(
        'minecraft:damage',
        _writeVarInt(next),
      );
      await inventory.setItemInHand(
        hand: e.hand,
        item: await HostStacks.write(damaged),
      );
      return;
    }

    // `ItemStackTemplate remainderTemplate = heldItem.getItem().getCraftingRemainder();`
    final remainder = craftingRemainderOf(held);
    final rest = held.shrink(1);
    if (rest.isEmpty) {
      // `player.setItemInHand(hand, leftover)`: the hand takes the remainder.
      await inventory.setItemInHand(
        hand: e.hand,
        item: remainder == null ? null : await HostStacks.write(remainder),
      );
      return;
    }
    await inventory.setItemInHand(
      hand: e.hand,
      item: await HostStacks.write(rest),
    );
    if (remainder == null) return;
    // `player.getInventory().add(leftover)`, dropped at the player when it is full.
    await giveToPlayerStack(e.player, e.player.getWorld(), remainder);
  }

  /// `awardAdvancements(event.getEntity(), transformedBlock)`.
  static Future<void> _award(
    ProcessingRuntime rt,
    Player player,
    String? block,
  ) async {
    final id = switch (block) {
      'create:andesite_casing' => AllAdvancements.andesiteCasing,
      'create:brass_casing' => AllAdvancements.brassCasing,
      'create:copper_casing' => AllAdvancements.copperCasing,
      'create:railway_casing' => AllAdvancements.trainCasing,
      _ => null,
    };
    if (id == null) return;
    final advancements = rt.services.find<CreateAdvancements>();
    if (advancements == null || !advancements.canAward(id)) return;
    try {
      await advancements.award(player, id);
    } on Object {
      // an advancement that is already granted, or a host that cannot grant it
    }
  }

  /// `EnchantmentHelper.getLevel(UNBREAKING, stack)` of the held item.
  static Future<int> _unbreakingLevel(ItemStack stack) async {
    try {
      return await stack.enchantmentLevelOf('minecraft:unbreaking');
    } on Object {
      return 0;
    }
  }

  static int _readVarInt(List<int>? bytes) {
    if (bytes == null) return 0;
    var value = 0;
    var shift = 0;
    for (final b in bytes) {
      value |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 35) break;
    }
    return value;
  }

  static List<int> _writeVarInt(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      if ((v & ~0x7f) == 0) {
        out.add(v);
        return out;
      }
      out.add((v & 0x7f) | 0x80);
      v >>>= 7;
    }
  }
}