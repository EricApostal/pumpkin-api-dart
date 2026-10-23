// `BeltDeployerCallbacks`: a deployer facing down processes the items of the belt or depot below
// it with its held item (`create:deploying` and `create:item_application` recipes).
//
// Ported from `content/kinetics/deployer/BeltDeployerCallbacks.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show giveToPlayerStack;
import '../processing_runtime.dart';
import '../recipe/recipe_applier.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../support/kinetics_bridge.dart';
import '../transport/transported_stack.dart';
import 'deployer_block_entity.dart';
import 'deployer_items.dart';
import 'deployer_types.dart';

/// The callbacks the deployer's `BeltProcessingBehaviour` uses.
abstract final class BeltDeployerCallbacks {
  /// `onItemReceived`.
  static ProcessingResult onItemReceived(
    TransportedItemStack transported,
    TransportedItemStackHandler inventory,
    DeployerBlockEntity be,
  ) {
    if (be.speed == 0) return ProcessingResult.pass;
    if (be.mode == DeployerMode.punch) return ProcessingResult.pass;
    if (be.blockState.dirOf('facing') != Dir.down) return ProcessingResult.pass;
    if (be.state != DeployerState.waiting) return ProcessingResult.hold;
    if (be.redstoneLocked) return ProcessingResult.pass;
    if (be.heldItem.isEmpty) return ProcessingResult.hold;
    if (be.getRecipe(transported.stack) == null) return ProcessingResult.pass;

    unawaited(be.start());
    return ProcessingResult.hold;
  }

  /// `whenItemHeld`.
  static ProcessingResult whenItemHeld(
    TransportedItemStack transported,
    TransportedItemStackHandler inventory,
    DeployerBlockEntity be,
  ) {
    if (be.speed == 0) return ProcessingResult.pass;
    if (be.blockState.dirOf('facing') != Dir.down) return ProcessingResult.pass;
    if (be.heldItem.isEmpty) return ProcessingResult.hold;

    final recipe = be.getRecipe(transported.stack);
    if (recipe == null) return ProcessingResult.pass;

    if (be.state == DeployerState.retracting && be.timer == 1000) {
      unawaited(activate(transported, inventory, be, recipe));
      return ProcessingResult.hold;
    }

    if (be.state == DeployerState.waiting) {
      if (be.redstoneLocked) return ProcessingResult.pass;
      unawaited(be.start());
    }
    return ProcessingResult.hold;
  }

  /// `activate`: applies [match] to the transported item, consuming the deployer's held item.
  static Future<void> activate(
    TransportedItemStack transported,
    TransportedItemStackHandler handler,
    DeployerBlockEntity be,
    RecipeMatch match,
  ) async {
    final rt = ProcessingRuntime.instance;
    final world = be.world;

    final results = <PStack>[];
    for (final rolled in match.rollResults(rt.random)) {
      addToList(rolled, results);
    }
    if (!match.recipe.keepHeldItem) {
      // The crafting remainder of the processed item (`returnProcessingRemainder`).
      final remainder = craftingRemainderOf(transported.stack);
      if (remainder != null) addToList(remainder, results);
    }

    final collect = <TransportedItemStack>[
      for (final stack in results)
        (transported.copy()
          ..stack = stack
          ..locked = false
          ..angle = transportedAngleFor(stack, rt.tags, rt.random)),
    ];

    // `blockEntity.award(DEPLOYER)` (`BeltDeployerCallbacks.java:119`): the belt or depot
    // below the deployer is processed by `BeltDeployerCallbacks` (not by the block's own use),
    // so the trigger fires here.
    unawaited(be.advancements.awardPlayer(AllAdvancements.deployer));

    // `clearFanProcessingData`.
    transported.processedBy = null;
    transported.processingTime = 0;

    final left = transported.copy();
    left.stack = left.stack.shrink(1);

    final PStack resultItem;
    if (collect.isEmpty) {
      resultItem = left.stack;
      handler.handleProcessingOnItem(
        transported,
        TransportedResult.convertTo(left),
      );
    } else {
      resultItem = collect.first.stack;
      handler.handleProcessingOnItem(
        transported,
        TransportedResult.convertToAndLeaveHeld(collect, left),
      );
    }

    if (!match.recipe.keepHeldItem) {
      await _consumeHeld(be, be.player, world, rt);
    }

    if (world != null) {
      final pos = (be.pos.x + .5, be.pos.y + .5, be.pos.z + .5);
      if (be.heldItem.isEmpty) {
        world.playSound(
          sound: Sound.entityItemBreak,
          category: SoundCategory.blocks,
          pos: pos,
          volume: .25,
          pitch: 1,
        );
      }
      world.playSound(
        sound: Sound.entityItemPickup,
        category: SoundCategory.blocks,
        pos: pos,
        volume: .25,
        pitch: .75,
      );
      if (match.recipe.type == CreateRecipeType.sandpaperPolishing) {
        world.playCustomSound(
          soundName: 'create:sanding_short',
          category: SoundCategory.blocks,
          pos: pos,
          volume: .35,
          pitch: 1,
        );
      }
    }

    be.markDirty();
    be.sendData();
    // The remainder went into the fake player's inventory: keep the saved copy in step.
    await be.snapshotInventory();
    // `awardAdvancements` is only an advancement trigger; the host has no portable hook here.
    if (resultItem.isEmpty) return;
  }

  /// `heldItem.hurtAndBreak(1, player, MAINHAND)` for a damageable item, the item's crafting
  /// remainder otherwise, then `shrink(1)` (`BeltDeployerCallbacks.activate`).
  static Future<void> _consumeHeld(
    DeployerBlockEntity be,
    Player? player,
    World? world,
    ProcessingRuntime rt,
  ) async {
    final held = be.heldItem;
    if (held.isEmpty) return;

    final max = _readVarInt(held.component('minecraft:max_damage'));
    if (max > 0) {
      // `ItemStack.hurtAndBreak`: `minecraft:unbreaking` can negate the point of damage
      // (`EnchantmentHelper.processDurabilityChange`, 1 in level+1 per point).
      var damage = 1;
      final level = await _unbreakingLevel(player);
      if (level > 0) {
        for (var i = 0; i < damage; i++) {
          if (rt.random.nextDouble() < 1 / (level + 1)) damage--;
        }
      }
      if (damage <= 0) return;

      final next = _readVarInt(held.component('minecraft:damage')) + damage;
      // A broken item is gone from the hand (`applyDamage` shrinks it away); the deployer's own
      // `ITEM_BREAK` sound below is what a fake player's break event amounts to.
      await be.setHeld(
        next >= max
            ? PStack.empty
            : held.withComponent('minecraft:damage', _writeVarInt(next)),
      );
      return;
    }

    final remainder = craftingRemainderOf(held);
    final rest = held.shrink(1);
    if (rest.isEmpty) {
      // `player.setItemInHand(MAIN_HAND, leftover)`: the hand takes the remainder.
      await be.setHeld(remainder ?? PStack.empty);
      return;
    }

    await be.setHeld(rest);
    if (remainder == null) return;
    // `player.getInventory().add(leftover)`, and dropped at the player when it is full.
    if (player != null && world != null) {
      await giveToPlayerStack(player, world, remainder);
    } else {
      be.overflowItems.add(remainder);
    }
  }

  /// `EnchantmentHelper.getLevel(UNBREAKING, stack)` of the item in the fake player's hand.
  static Future<int> _unbreakingLevel(Player? player) async {
    final hand = player?.getItemInHand(hand: Hand.right);
    if (hand == null) return 0;
    try {
      return await hand.enchantmentLevelOf('minecraft:unbreaking');
    } on Object {
      return 0;
    } finally {
      hand.dispose();
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
