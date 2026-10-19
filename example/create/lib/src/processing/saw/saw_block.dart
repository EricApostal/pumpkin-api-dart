// `SawBlock` / `SawBlockEntity`: the mechanical saw. Facing up it cuts items (the `create:cutting`
// recipes and vanilla stonecutting); facing sideways it fells blocks in front of it, whole trees
// included, and hurts entities that touch it. Ported from
// `content/kinetics/saw/SawBlock.java`, `SawBlockEntity.java` and `CuttingRecipe.java`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../support/kinetics_bridge.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe_applier.dart';
import '../transport/transport_behaviours.dart';
import 'block_breaking.dart';
import 'processing_inventory.dart';
import 'saw_filter.dart';
import 'saw_recipes.dart';
import 'tree_cutter.dart';

/// `SawBlock.FLIPPED` + `DirectionalAxisKineticBlock.AXIS_ALONG_FIRST_COORDINATE`: a horizontal
/// shaft, the blade along it.
class SawBlockDef extends KineticBlockDef {
  const SawBlockDef();

  Dir facing(KState s) => s.dirOf('facing') ?? Dir.north;

  /// `SawBlock.isHorizontal`.
  bool isHorizontal(KState s) => facing(s).axis.isHorizontal;

  @override
  KAxis rotationAxis(KState state) {
    final f = facing(state);
    if (f.axis.isHorizontal) return f.axis;
    // DirectionalAxisKineticBlock: the piston axis is Y.
    return state.flag('axis_along_first') ? KAxis.x : KAxis.z;
  }

  @override
  bool hasShaftTowards(KState state, Dir face) {
    final f = facing(state);
    if (f.axis.isHorizontal) return face == f.opposite;
    return face.axis == rotationAxis(state);
  }
}

/// `SawBlockEntity`.
final class SawBlockEntity extends BlockBreakingKineticBlockEntity
    implements ItemStorageProvider {
  SawBlockEntity(super.worldId, super.pos) {
    final configs = ProcessingRuntime.isLoaded
        ? ProcessingRuntime.instance.configs
        : null;
    final bulk = configs?.server.recipes.bulkCutting.value ?? false;
    inventory = ProcessingInventory(limitToOne: !bulk);
    filter = addBehaviour(SawFilterBehaviour());
    beltInput = addBehaviour(
      DirectBeltInputBehaviour()
        ..allowingBeltFunnelsWhen(canProcess)
        ..defaultInsertion = _insertFromBelt,
    );
  }

  /// `inventory`: slot 0 is the input, the rest hold the results.
  late final ProcessingInventory inventory;

  /// `filtering`: the filter of the recipe results.
  late final SawFilterBehaviour filter;

  /// The `DirectBeltInputBehaviour` the saw offers to belts and funnels.
  late final DirectBeltInputBehaviour beltInput;

  /// `recipeIndex`.
  int recipeIndex = 0;

  @override
  bool get syncsToClient => true;

  // -- Capabilities ---------------------------------------------------------------------------

  @override
  ItemStorage? itemStorage(String? side) => side == 'down' ? null : inventory;

  // -- Lifecycle ------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Inventory', inventory.writeNbt());
    tag.putInt('RecipeIndex', recipeIndex);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final inv = tag.getCompound('Inventory');
    if (inv != null) inventory.readNbt(inv);
    recipeIndex = tag.getInt('RecipeIndex') ?? 0;
  }

  // -- Block breaker --------------------------------------------------------------------------

  @override
  bool shouldRun() =>
      (blockState.dirOf('facing') ?? Dir.north).axis.isHorizontal;

  @override
  Pos getBreakingPos() {
    final facing = blockState.dirOf('facing') ?? Dir.north;
    return (pos.x + facing.dx, pos.y + facing.dy, pos.z + facing.dz);
  }

  @override
  bool canBreakState(BlockState stateToBreak, double blockHardness) =>
      super.canBreakState(stateToBreak, blockHardness) &&
      isSawable(
        BState(stateToBreak.blockName, {
          for (final p in stateToBreak.properties) p.$1: p.$2,
        }),
        (s, tag) => Tags.block(s.key, tag),
      );

  @override
  Future<void> onBlockBrokenState(BlockState stateToBreak) async {
    final w = world;
    if (w == null) return;
    final bp = breakingPos;
    if (bp == null) return;
    final brokenState = BState(stateToBreak.blockName, {
      for (final p in stateToBreak.properties) p.$1: p.$2,
    });
    // `super.onBlockBroken` destroys the block that was cut first, then the rest of the tree is
    // searched from the now empty position.
    await super.onBlockBrokenState(stateToBreak);
    final tree = findTree(
      stateAt: (p) => _stateAt(w, p),
      hasTag: (s, tag) => Tags.block(s.key, tag),
      height: 384,
      pos: bp,
      brokenState: brokenState,
    );
    if (tree.isEmpty) return;
    await _destroyTree(w, bp, tree);
  }

  BState _stateAt(World world, Pos p) {
    final s = world.getBlockState(pos: p.toBlockPos());
    return BState(s.blockName, {for (final e in s.properties) e.$1: e.$2});
  }

  /// `Tree.destroyBlocks` with `dropItemFromCutTree`.
  Future<void> _destroyTree(World world, Pos origin, CutTree tree) async {
    final futures = <Future<void>>[];
    tree.destroyBlocks((p) {
      futures.add(() async {
        await BlockHelper.destroyBlockWith(world, p, 1, (stack) async {
          final dx = p.x - origin.x, dy = p.y - origin.y, dz = p.z - origin.z;
          final distance = math.sqrt((dx * dx + dy * dy + dz * dz).toDouble());
          final velocity = (
            dx * distance / 20,
            dy * distance / 20,
            dz * distance / 20,
          );
          await world.dropItem(
            p.center,
            stack,
            velocity: velocity,
            pickupDelay: 10,
          );
        });
      }());
    });
    await Future.wait(futures);
  }

  // -- Cutting --------------------------------------------------------------------------------

  /// `canProcess`: the saw cuts only while its blade points up.
  bool canProcess() => (blockState.dirOf('facing') ?? Dir.north) == Dir.up;

  @override
  void tick() {
    if (shouldRun() && ticksUntilNextProgress < 0) destroyNextTick();
    super.tick();

    if (!canProcess() || speed == 0) return;
    if (inventory.remainingTime == -1) {
      if (!inventory.isEmpty && !inventory.appliedRecipe) {
        start(inventory.stackIn(0));
      }
      return;
    }

    final processingSpeed = ((speed.abs() / 24).clamp(1.0, 128.0)).toDouble();
    inventory.remainingTime -= processingSpeed;

    if (inventory.remainingTime < 5 && !inventory.appliedRecipe) {
      applyRecipe();
      inventory.appliedRecipe = true;
      inventory.recipeDuration = 20;
      inventory.remainingTime = 20;
      sendData();
      return;
    }

    if (inventory.remainingTime > 0) return;
    inventory.remainingTime = 0;

    final movement = getItemMovementVec();
    final movementFacing = Dir.approximateNearest(
      movement.$1,
      movement.$2,
      movement.$3,
    );
    final nextPos = (
      pos.x + movement.$1.toInt(),
      pos.y + movement.$2.toInt(),
      pos.z + movement.$3.toInt(),
    );
    final next = store.at(worldId, nextPos.toBlockPos());
    final behaviour = next?.getBehaviour<DirectBeltInputBehaviour>();
    if (behaviour != null) {
      if (!behaviour.canInsertFromSide(movementFacing.name)) return;
      var changed = false;
      for (var slot = 0; slot < inventory.slots; slot++) {
        final stack = inventory.stackIn(slot);
        if (stack.isEmpty) continue;
        final remainder = behaviour.handleInsertion(
          TransportedItemStack(stack),
          movementFacing.name,
          false,
        );
        if (remainder == stack) continue;
        inventory.setStack(slot, remainder);
        changed = true;
      }
      if (changed) {
        markDirty();
        sendData();
      }
      return;
    }

    _ejectItems(movement);
  }

  /// `getItemMovementVec`: the direction the results leave the saw in.
  Vec3 getItemMovementVec() {
    final alongX = !blockState.flag('axis_along_first');
    final offset = speed < 0 ? -1 : 1;
    return (offset * (alongX ? 1 : 0), 0, offset * (alongX ? 0 : -1));
  }

  /// `getRecipes`.
  List<SawRecipe> getRecipes() {
    if (!ProcessingRuntime.isLoaded) return const [];
    final rt = ProcessingRuntime.instance;
    final cache = SawRecipeCache.current;
    final configs = rt.configs;
    return sawRecipes(
      rt.recipes,
      inventory.stackIn(0),
      filter: filter.test,
      allowStonecutting:
          configs?.server.recipes.allowStonecuttingOnSaw.value ?? true,
      stonecutting: cache?.stonecutting ?? const [],
    );
  }

  /// `start(inserted)`.
  void start(PStack inserted) {
    if (!canProcess() || inventory.isEmpty) return;

    final recipes = getRecipes();
    if (recipes.isEmpty) {
      inventory.remainingTime = inventory.recipeDuration = 10;
      inventory.appliedRecipe = false;
      sendData();
      return;
    }

    recipeIndex++;
    if (recipeIndex >= recipes.length) recipeIndex = 0;

    final recipe = recipes[recipeIndex];
    final time = recipe.duration;
    inventory.remainingTime = (time * math.max(1, inserted.count ~/ 5))
        .toDouble();
    inventory.recipeDuration = inventory.remainingTime;
    inventory.appliedRecipe = false;
    sendData();
  }

  /// `applyRecipe`.
  void applyRecipe() {
    final input = inventory.stackIn(0);
    if (input.isEmpty) return;
    final recipes = getRecipes();
    if (recipes.isEmpty) return;
    if (recipeIndex >= recipes.length) recipeIndex = 0;
    final recipe = recipes[recipeIndex];

    final results = recipe.apply(input, ProcessingRuntime.instance.random);
    inventory.clearAll();
    final merged = <PStack>[];
    for (final stack in results) {
      addToList(stack, merged);
    }
    for (
      var slot = 0;
      slot < merged.length && slot + 1 < inventory.slots;
      slot++
    ) {
      inventory.setStack(slot + 1, merged[slot]);
    }
  }

  /// `insertItem`: a dropped item that fell onto an upward saw starts the next recipe.
  Future<void> insertItem(ItemEntity entity) async {
    if (!canProcess() || !inventory.isEmpty) return;
    final stack = await HostStacks.read(entity.getStack());
    if (stack.isEmpty) return;
    inventory.clearAll();
    final remainder = inventory.insert(0, stack);
    if (remainder.isEmpty) {
      entity.discard();
    } else {
      final item = await HostStacks.write(remainder);
      if (item != null) await entity.setStack(stack: item);
    }
    start(inventory.stackIn(0));
  }

  /// `SawBlock.useItemOn` with an empty hand: the contents go back to the player.
  Future<void> dropInventoryTo(Player player, World world) async {
    await dropContentsToPlayer(inventory, player, world, pos.toPos());
    inventory.clearAll();
    sendData();
  }

  /// The default insertion of the [DirectBeltInputBehaviour] (belts put items into slot 0).
  PStack _insertFromBelt(
    TransportedItemStack inserted,
    String side,
    bool simulate,
  ) {
    if (!canProcess() || !inventory.isEmpty) return inserted.stack;
    final rest = inventory.insert(0, inserted.stack, simulate: simulate);
    if (!simulate && rest.count != inserted.stack.count) {
      start(inventory.stackIn(0));
    }
    return rest;
  }

  /// The "Eject Items" branch of `tick`.
  void _ejectItems(Vec3 movement) {
    final w = world;
    if (w == null) return;
    final outPos = (
      pos.x + .5 + movement.$1 * .5,
      pos.y + .5 + .5,
      pos.z + .5 + movement.$3 * .5,
    );
    final outMotion = (movement.$1 * .0625, .125, movement.$3 * .0625);
    final stacks = [
      for (var slot = 0; slot < inventory.slots; slot++)
        inventory.stackIn(slot),
    ];
    inventory.clearAll();
    inventory.remainingTime = -1;
    sendData();
    unawaited(() async {
      for (final stack in stacks) {
        if (stack.isEmpty) continue;
        final item = await HostStacks.write(stack);
        if (item == null) continue;
        await w.dropItem(outPos, item, velocity: outMotion);
      }
    }());
  }
}

/// The stonecutting recipes the saw may use, loaded from the host recipe manager by the part.
final class SawRecipeCache {
  static SawRecipeCache? current;

  List<StonecuttingRecipe> stonecutting = const [];
}
