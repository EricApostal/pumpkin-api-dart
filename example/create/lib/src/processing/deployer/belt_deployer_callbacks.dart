// `BeltDeployerCallbacks`: a deployer facing down processes the items of the belt or depot below
// it with its held item (`create:deploying` and `create:item_application` recipes).
//
// Ported from `content/kinetics/deployer/BeltDeployerCallbacks.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/stack.dart';
import '../processing_runtime.dart';
import '../recipe/recipe_applier.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../support/kinetics_bridge.dart';
import '../transport/transported_stack.dart';
import 'deployer_block_entity.dart';
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
      final remainder = _craftingRemainder(transported.stack.key);
      if (remainder != null) addToList(remainder, results);
    }

    final collect = <TransportedItemStack>[
      for (final stack in results)
        (transported.copy()
          ..stack = stack
          ..locked = false
          ..angle = rt.random.nextInt(360)),
    ];

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
      await _consumeHeld(be, rt);
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
    // `awardAdvancements` is only an advancement trigger; the host has no portable hook here.
    if (resultItem.isEmpty) return;
  }

  /// `heldItem.hurtAndBreak(1)` or the item's crafting remainder, then `shrink(1)`.
  static Future<void> _consumeHeld(
    DeployerBlockEntity be,
    ProcessingRuntime rt,
  ) async {
    final held = be.heldItem;
    if (held.isEmpty) return;

    if (held.hasComponent('minecraft:max_damage')) {
      final damage = _readVarInt(held.component('minecraft:damage'));
      final max = _readVarInt(held.component('minecraft:max_damage'));
      final next = damage + 1;
      if (next >= max && max > 0) {
        be.heldItem = PStack.empty;
      } else {
        be.heldItem = held.withComponent(
          'minecraft:damage',
          _writeVarInt(next),
        );
      }
      await be.setHeld(be.heldItem);
      return;
    }

    final remainder = _craftingRemainder(held.key);
    var rest = held.shrink(1);
    if (rest.isEmpty) {
      be.heldItem = remainder ?? PStack.empty;
    } else {
      be.heldItem = rest;
    }
    await be.setHeld(be.heldItem);
    if (remainder != null && rest.isNotEmpty) {
      // The remainder goes to the deployer's overflow (`player.getInventory().add`).
      be.overflowItems.add(remainder);
    }
  }

  /// `Item.getCraftingRemainder` for the common container items (the host has no item API for
  /// it).
  static PStack? _craftingRemainder(String key) => switch (key) {
    'minecraft:water_bucket' ||
    'minecraft:lava_bucket' ||
    'minecraft:milk_bucket' => const PStack('minecraft:bucket', 1),
    'minecraft:honey_bottle' => const PStack('minecraft:glass_bottle', 1),
    _ => null,
  };

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
