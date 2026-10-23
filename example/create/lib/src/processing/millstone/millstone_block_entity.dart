// `MillstoneBlockEntity`: a kinetic machine that grinds one item at a time with a
// `create:milling` recipe. The input (1 slot) and the output (9 slots) are one combined
// handler for hoppers and belts: insertion into the input, extraction from the output.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/kinetics.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../deployer/deployer_items.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../transport/transport_behaviours.dart';
import 'millstone_keys.dart';
import 'millstone_storage.dart';

class MillstoneBlockEntity extends KineticBlockEntity
    implements ItemStorageProvider {
  static const String type = millstoneKey;

  late final SmartInventory inputInv;
  late final SmartInventory outputInv;
  late final MillstoneStorage capability;

  /// `timer`: ticks left until the current item is done.
  int timer = 0;

  /// `lastRecipe`: the recipe the input matched last (transient, as in Java).
  RecipeMatch? lastMatch;

  /// `registerAwardables(behaviours, MILLSTONE)` (`MillstoneBlockEntity.java:71`): the millstone
  /// awards its owner.
  late final AdvancementBehaviour advancements;

  MillstoneBlockEntity(super.worldId, super.pos) {
    advancements = addBehaviour(
      AdvancementBehaviour(
        [AllAdvancements.millstone],
        () => ProcessingRuntime.instance.advancements,
      ),
    );
    inputInv = SmartInventory(1, onChanged: (_) => markDirty());
    outputInv = SmartInventory(9, onChanged: (_) => markDirty());
    capability = MillstoneStorage(inputInv, outputInv, canProcess: _canProcess);
    addBehaviour(
      DirectBeltInputBehaviour()
        ..defaultInsertion = (inserted, side, simulate) =>
            ItemStorages.insertStacked(
              capability,
              inserted.stack,
              simulate: simulate,
            ),
    );
  }

  @override
  ItemStorage? itemStorage(String? side) => capability;

  /// `getProcessingSpeed()`: one tick of progress per 16 RPM, 1 to 512 per tick.
  int get processingSpeed => (speed.abs() / 16).toInt().clamp(1, 512);

  // -- Recipes -------------------------------------------------------------------------------

  RecipeMatch? _findRecipe(PStack stack) {
    if (stack.isEmpty) return null;
    return ProcessingRuntime.instance.recipes.findForInput(
      CreateRecipeType.milling,
      stack,
      allowSequenced: false,
    );
  }

  /// `canProcess(stack)`.
  bool _canProcess(PStack stack) {
    if (stack.isEmpty) return false;
    final last = lastMatch;
    if (last != null &&
        last.recipe.matchesSingle(stack, ProcessingRuntime.instance.tags)) {
      return true;
    }
    return _findRecipe(stack) != null;
  }

  // -- Ticking -------------------------------------------------------------------------------

  @override
  void tick() {
    super.tick();

    if (speed == 0) return;
    // Do not start another item while a result slot is full.
    for (var i = 0; i < outputInv.slots; i++) {
      if (outputInv.stackIn(i).count >= outputInv.slotLimit(i)) return;
    }

    if (timer > 0) {
      timer -= processingSpeed;
      if (timer <= 0) process();
      return;
    }

    final input = inputInv.stackIn(0);
    if (input.isEmpty) return;

    final tags = ProcessingRuntime.instance.tags;
    final last = lastMatch;
    if (last == null || !last.recipe.matchesSingle(input, tags)) {
      final match = _findRecipe(input);
      if (match == null) {
        timer = 100;
        sendData();
      } else {
        lastMatch = match;
        timer = match.recipe.processingDuration;
        sendData();
      }
      return;
    }
    timer = last.recipe.processingDuration;
    sendData();
  }

  /// `process()`: consume one item and roll the results into the output.
  void process() {
    final stack = inputInv.stackIn(0);
    if (stack.isEmpty) return;

    final match = _findRecipe(stack);
    if (match == null) return;
    lastMatch = match;

    // `MillstoneBlockEntity.java:164-167`: the remainder is read from the input before it is
    // shrunk; `:170-172`: it is inserted after the rolled results, when it is not empty.
    final remainder = craftingRemainderOf(stack);
    inputInv.setStack(0, stack.shrink(1));
    final random = ProcessingRuntime.instance.random;
    for (final result in match.rollResults(random)) {
      ItemStorages.insertStacked(outputInv, result);
    }
    if (remainder != null && !remainder.isEmpty) {
      ItemStorages.insertStacked(outputInv, remainder);
    }
    // `award(AllAdvancements.MILLSTONE)` (`MillstoneBlockEntity.java:173`): after the results
    // land in the output.
    unawaited(advancements.awardPlayer(AllAdvancements.millstone));
    markDirty();
    sendData();
  }

  // -- Player interaction --------------------------------------------------------------------

  /// `MillstoneBlock.useItemOn` with an empty hand: give the output back, or the input when
  /// there is no output yet.
  Future<void> emptyIntoPlayer(Player player, World world) async {
    var emptyOutput = true;
    for (var slot = 0; slot < outputInv.slots; slot++) {
      final stack = outputInv.stackIn(slot);
      if (stack.isEmpty) continue;
      emptyOutput = false;
      await _give(player, world, stack);
      outputInv.setStack(slot, PStack.empty);
    }

    if (emptyOutput) {
      for (var slot = 0; slot < inputInv.slots; slot++) {
        final stack = inputInv.stackIn(slot);
        if (stack.isEmpty) continue;
        await _give(player, world, stack);
        inputInv.setStack(slot, PStack.empty);
      }
    }

    markDirty();
    sendData();
  }

  /// `Inventory.placeItemBackInInventory`: leftovers are dropped at the player.
  static Future<void> _give(Player player, World world, PStack stack) async {
    final host = await HostStacks.write(stack);
    if (host == null) return;
    final left = await player.give(host);
    if (left != null) await world.dropItem(player.getPosition(), left);
  }

  /// `MillstoneBlock.fallOn`: an item that lands on the millstone goes into its input.
  Future<void> insertDroppedItem(ItemEntity item) async {
    final stack = await HostStacks.read(item.getStack());
    final remainder = capability.insert(0, stack);
    if (remainder.isEmpty) {
      item.discard();
      return;
    }
    if (remainder.count < stack.count) {
      final host = await HostStacks.write(remainder);
      if (host != null) await item.setStack(stack: host);
    }
  }

  // -- Persistence ---------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('Timer', timer);
    tag.putCompound('InputInventory', StackNbt.writeList(inputInv.contents));
    tag.putCompound('OutputInventory', StackNbt.writeList(outputInv.contents));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    timer = tag.getInt('Timer') ?? 0;
    inputInv.load(
      StackNbt.readList(tag.getCompound('InputInventory'), inputInv.slots),
    );
    outputInv.load(
      StackNbt.readList(tag.getCompound('OutputInventory'), outputInv.slots),
    );
  }

  /// `destroy()`: the contents are dropped when the millstone is broken.
  @override
  void onRemoved() {
    super.onRemoved();
    final w = world;
    if (w == null) return;
    unawaited(
      () async {
        for (final stack in [...inputInv.contents, ...outputInv.contents]) {
          if (stack.isEmpty) continue;
          final host = await HostStacks.write(stack);
          if (host != null) {
            await w.dropItem((pos.x + .5, pos.y + .5, pos.z + .5), host);
          }
        }
        inputInv.clear();
        outputInv.clear();
      }().catchError((Object e, StackTrace s) {
        ProcessingRuntime.instance.log.error(
          'Dropping the contents of the millstone at ${pos.x}, ${pos.y}, ${pos.z} failed',
          error: e,
          stackTrace: s,
        );
      }),
    );
  }
}
