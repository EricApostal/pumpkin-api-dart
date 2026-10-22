// `BasinBlock`: the basin's block, its shapes, the spout facing and the interactions with
// players (emptying), falling items and comparators. The block entity is in
// `basin_block_entity.dart`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../fluids/fluid_processing_bridge.dart';
import '../../fluids/fluid_runtime.dart';
import '../../fluids/generic_item_fluid.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/heat.dart';
import '../recipe/ingredient.dart';
import '../support/kinetics_bridge.dart';
import '../transport/transport_behaviours.dart';
import 'basin_block_entity.dart';

/// `BasinBlock`.
abstract final class BasinBlock {
  static const String key = 'create:basin';

  /// `FACING_HOPPER` (the spout side); `down` when the outputs stay in the basin.
  static const String facingProperty = 'facing';

  /// `AllShapes.BASIN_BLOCK_SHAPE`: the four walls from 2px up, and the floor.
  static final BlockShape shape = BlockShape.boxes(const [
    BlockBox(0, 2 / 16, 0, 2 / 16, 1, 1),
    BlockBox(14 / 16, 2 / 16, 0, 1, 1, 1),
    BlockBox(2 / 16, 2 / 16, 0, 14 / 16, 1, 2 / 16),
    BlockBox(2 / 16, 2 / 16, 14 / 16, 14 / 16, 1, 1),
    BlockBox(2 / 16, 0, 2 / 16, 14 / 16, 2 / 16, 14 / 16),
  ]);

  /// `AllShapes.BASIN_COLLISION_SHAPE`: lower walls so items fall in, and the floor.
  static final BlockShape collisionShape = BlockShape.boxes(const [
    BlockBox(0, 2 / 16, 0, 1, 5 / 16, 1),
    BlockBox(0, 5 / 16, 0, 2 / 16, 13 / 16, 1),
    BlockBox(14 / 16, 5 / 16, 0, 1, 13 / 16, 1),
    BlockBox(2 / 16, 5 / 16, 0, 14 / 16, 13 / 16, 2 / 16),
    BlockBox(2 / 16, 5 / 16, 14 / 16, 14 / 16, 13 / 16, 1),
    BlockBox(2 / 16, 0, 2 / 16, 14 / 16, 2 / 16, 14 / 16),
  ]);

  /// `AllShapes.BASIN_RAYTRACE_SHAPE`: a solid interior so the whole basin is clickable.
  static final BlockShape rayTraceShape = BlockShape.boxes(const [
    BlockBox(0, 2 / 16, 0, 1, 1, 1),
    BlockBox(2 / 16, 0, 2 / 16, 14 / 16, 2 / 16, 14 / 16),
  ]);

  static ProcessingRuntime get _rt => ProcessingRuntime.instance;

  /// `BasinBlock.isBasin(level, pos)`: the block entity at [pos] is a basin.
  static bool isBasin(BlockEntityStore store, String worldId, Pos pos) =>
      store.at(worldId, pos.toBlockPos()) is BasinBlockEntity;

  /// `BasinBlock.canSurvive`: no basin operating machine may sit right above a basin.
  static bool canSurvive(World world, Pos pos) {
    final above = HostBlockGetter(world).stateAt(pos.above).key;
    return above != 'create:mechanical_press' &&
        above != 'create:mechanical_mixer';
  }

  /// The `create:basin` block, from the manifest.
  static CreateBlock build() => createBlockFromManifest(
    'basin',
    blockEntityType: BasinBlockEntity.type,
    collisionShape: collisionShape,
    selectionShape: shape,
    behavior: BlockBehavior(
      onCanPlace: (server, e) => canSurvive(e.targetWorld, e.pos.toPos()),
      onUse: _onUse,
      onComparatorOutput: _comparatorOutput,
      onLandedUpon: _onLandedUpon,
      isPathfindable: (server, e) => false,
    ),
  );

  /// `useItemOn`: an empty hand takes the input items back; a held item empties its fluid into
  /// the basin or takes the basin's fluid (`FluidHelper.tryEmptyItemIntoBE` /
  /// `tryFillItemFromBE`), and a sponge soaks the basin's fluid up.
  static Future<BlockUseResult> _onUse(
    Server server,
    CustomBlockUseEventData e,
  ) async {
    final worldId = _rt.worlds.touch(e.targetWorld);
    final be = _rt.store.typed<BasinBlockEntity>(worldId, e.pos);
    if (be == null) return BlockUseResult.tryEmptyHand;

    if (e.withItem) {
      // `FluidHelper.tryEmptyItemIntoBE` / `tryFillItemFromBE`: the basin's fluid capability is
      // the combined output + input tanks (`BasinBlockEntity.fluidCapability`), which is what
      // the basin's own storage offers here too.
      final storage = be.fluidStorage(null);
      if (storage == null) return BlockUseResult.tryEmptyHand;
      if (!FluidsRuntime.isLoaded) return BlockUseResult.tryEmptyHand;

      final runtime = FluidsRuntime.instance;
      final emptying = GenericItemEmptying(runtime.rules, runtime.recipes);
      final filling = GenericItemFilling(runtime.rules);
      final held = await HostStacks.read(e.item);
      if (held.isEmpty) return BlockUseResult.tryEmptyHand;
      final item = FluidItemSpec(held.key, held.count, held.comps);

      if (await _emptyItemIntoBasin(
        e,
        storage,
        emptying,
        item,
        be,
      )) {
        return BlockUseResult.success;
      }
      if (await _fillItemFromBasin(e, storage, filling, item, be)) {
        return BlockUseResult.success;
      }

      // A recognised item is consumed without an exchange (`InteractionResult.SUCCESS`).
      if (emptying.canItemBeEmptied(item) || filling.canItemBeFilled(item)) {
        return BlockUseResult.success;
      }
      // `stack.getItem().equals(Items.SPONGE)`: a sponge takes the basin's fluid, nothing back.
      if (held.key == 'minecraft:sponge') {
        final drained = storage.drainAny(0x7fffffff);
        if (drained.isNotEmpty) {
          be.sendData();
          return BlockUseResult.success;
        }
      }
      return BlockUseResult.tryEmptyHand;
    }

    final inv = be.inputInventory;
    var success = false;
    for (var slot = 0; slot < inv.slots; slot++) {
      final stack = inv.stackIn(slot);
      if (stack.isEmpty) continue;
      await _giveOrDrop(e.player, e.targetWorld, e.pos.toPos(), stack);
      inv.setStack(slot, PStack.empty);
      success = true;
    }
    be.onEmptied();
    return success ? BlockUseResult.success : BlockUseResult.tryEmptyHand;
  }

  /// `FluidHelper.tryEmptyItemIntoBE`: whether the held item was emptied into the basin.
  static Future<bool> _emptyItemIntoBasin(
    CustomBlockUseEventData e,
    FluidStorage storage,
    GenericItemEmptying emptying,
    FluidItemSpec item,
    BasinBlockEntity be,
  ) async {
    if (!emptying.canItemBeEmptied(item)) return false;
    final (fluid, _, _) = emptying.emptyItem(item, simulate: true);
    final available = pFluidOf(fluid);
    if (available.isEmpty ||
        storage.fill(available, simulate: true) != available.amount) {
      return false;
    }

    final (emptied, remainder, newStack) = emptying.emptyItem(
      item,
      simulate: false,
    );
    storage.fill(pFluidOf(emptied));
    // The held item is consumed: the last item of the stack becomes its container in the hand,
    // an item of a bigger stack leaves the container in the inventory.
    if (!e.player.isCreative) {
      if (newStack.isEmpty) {
        await _setHand(e.player, e.hand, remainder);
      } else {
        await _setHand(e.player, e.hand, newStack);
        await _giveOrDrop(
          e.player,
          e.targetWorld,
          posContaining(e.player.getPosition()),
          PStack(remainder.key, remainder.count, comps: remainder.comps),
        );
      }
    }
    be.sendData();
    return true;
  }

  /// `FluidHelper.tryFillItemFromBE`: whether the held item took the basin's fluid.
  static Future<bool> _fillItemFromBasin(
    CustomBlockUseEventData e,
    FluidStorage storage,
    GenericItemFilling filling,
    FluidItemSpec item,
    BasinBlockEntity be,
  ) async {
    if (!filling.canItemBeFilled(item)) return false;
    for (var tank = 0; tank < storage.tanks; tank++) {
      final fluid = fStackOf(storage.fluidIn(tank));
      if (fluid.isEmpty) continue;
      final required = filling.getRequiredAmountForItem(
        item.withCount(1),
        fluid,
      );
      if (required == -1 || required > fluid.amount) continue;

      final (result, remaining, _) = filling.fillItem(required, item, fluid);
      if (result.isEmpty) continue;
      storage.drainFluid(storage.fluidIn(tank).withAmount(required));
      // `FluidHelper.tryFillItemFromBE`: the hand keeps its item for a creative player, a
      // survival player loses one and gets the filled container in the inventory.
      if (!e.player.isCreative) {
        await _setHand(e.player, e.hand, remaining);
        await _giveOrDrop(
          e.player,
          e.targetWorld,
          posContaining(e.player.getPosition()),
          PStack(result.key, result.count, comps: result.comps),
        );
      }
      be.sendData();
      return true;
    }
    return false;
  }

  /// `player.setItemInHand(hand, stack)`.
  static Future<void> _setHand(
    Player player,
    Hand hand,
    FluidItemSpec spec,
  ) async {
    if (spec.isEmpty) {
      await player.setItemInHand(hand: hand, stack: null);
      return;
    }
    final stack = await HostStacks.write(
      PStack(spec.key, spec.count, comps: spec.comps),
    );
    if (stack == null) return;
    await player.setItemInHand(hand: hand, stack: stack);
  }

  /// `ItemHelper.calcRedstoneFromInventory(inputInventory)`.
  static int? _comparatorOutput(
    Server server,
    CustomBlockComparatorOutputEventData e,
  ) {
    final be = _rt.store.typed<BasinBlockEntity>(
      _rt.worlds.touch(e.targetWorld),
      e.pos,
    );
    return be == null
        ? 0
        : ItemStorages.redstoneFromInventory(be.inputInventory);
  }

  /// `fallOn`: a dropped item that lands in the basin goes into its input inventory.
  static Future<double> _onLandedUpon(
    Server server,
    CustomBlockLandedEventData e,
  ) async {
    final worldId = _rt.worlds.touch(e.targetWorld);
    final be = _rt.store.typed<BasinBlockEntity>(worldId, e.pos);
    if (be == null) return e.damageMultiplier;

    final entity = e.targetWorld.getEntityById(id: e.entityId);
    final item = entity?.asItem();
    if (item == null) return e.damageMultiplier;
    // `if (!world.getBlockState(entity.blockPosition()).is(this)) return;`
    if (posContaining(entity!.getPosition()) != e.pos.toPos()) {
      return e.damageMultiplier;
    }

    final stack = await HostStacks.read(item.getStack());
    if (stack.isEmpty) return e.damageMultiplier;

    final rest = ItemStorages.insertStacked(be.inputInventory, stack);
    if (rest.isEmpty) {
      item.discard();
      return e.damageMultiplier;
    }
    final hostRest = await HostStacks.write(rest);
    if (hostRest != null) await item.setStack(stack: hostRest);
    return e.damageMultiplier;
  }

  static Future<void> _giveOrDrop(
    Player player,
    World world,
    Pos pos,
    PStack stack,
  ) async {
    final host = await HostStacks.write(stack);
    if (host == null) return;
    final left = await player.give(host);
    if (left != null) await world.dropItem(pos.center, left);
  }

  /// `BasinBlock.canOutputTo`: whether the spout may point at [direction].
  static bool canOutputTo(
    World world,
    String worldId,
    Pos basinPos,
    Direction direction,
  ) {
    final neighbour = basinPos.relative(direction);
    final output = neighbour.below;
    final getter = HostBlockGetter(world);
    final state = getter.stateAt(neighbour);

    if (isFunnel(state)) {
      if (funnelFacing(state) == direction) return false;
    } else if (!getter.collisionShapeEmpty(neighbour)) {
      return false;
    }

    final direct = _rt.store
        .at(worldId, output.toBlockPos())
        ?.getBehaviour<DirectBeltInputBehaviour>();
    if (direct != null) return direct.canInsertFromSide(direction.name);
    return false;
  }

  /// `FunnelBlock.isFunnel`.
  static bool isFunnel(BState state) =>
      state.key.startsWith('create:') && state.key.endsWith('_funnel');

  /// `FunnelBlock.getFunnelFacing`.
  static Direction? funnelFacing(BState state) => state.dir('facing');

  /// `BasinBlockEntity.getHeatLevelOf`: a blaze burner's heat level, or the passive heat of
  /// a `create:passive_boiler_heaters` block (lit campfires and the like).
  static HeatLevel heatLevelOf(BState state, TagLookup tags) {
    final blaze = state['blaze'];
    if (blaze != null) return HeatLevel.byName(blaze) ?? HeatLevel.none;
    if (tags.blockHasTag(state.key, 'create:passive_boiler_heaters') &&
        isNotUnheated(state)) {
      return HeatLevel.smouldering;
    }
    return HeatLevel.none;
  }

  /// `BlockHelper.isNotUnheated`: campfires must be lit; other heaters count as hot.
  static bool isNotUnheated(BState state) {
    if ((state.key == 'minecraft:campfire' ||
            state.key == 'minecraft:soul_campfire') &&
        state.has('lit')) {
      return state.flag('lit');
    }
    if (state.has('blaze')) return state['blaze'] != 'none';
    return true;
  }
}
