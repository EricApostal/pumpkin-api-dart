// The blocks of the fluids module: the pipes, the mechanical pump, the fluid
// valve, the tanks, the spout, the item drain and the hose pulley. The specs
// come from the manifest; this file adds the placement, neighbour, use and
// comparator behaviour and the block entity types.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show manifestBlock;
import '../api/wrenchable.dart';
import '../common/block_entity_item_data.dart';
import '../common/block_entity_item_data_host.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart'
    show BlockDirectionToPure, BlockStates, PosToHost;
import '../common/nbt_convert.dart' show compoundOf, valueOfCompound;
import '../common/pos.dart';
import '../core/nbt.dart' show NbtValue;
import '../contraptions/bearing/bearing_placement.dart' show bearingShaftNeighbours;
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/registry.dart';
import '../decoration/behaviour_support.dart' show stateIndexOf;
import '../decoration/bracketed_behaviour.dart';
import '../kinetics/behavior_builder.dart';
import '../kinetics/block_defs.dart';
import '../kinetics/geometry.dart' show Dir, KAxis, KState;
import '../processing/common/stack.dart' show PStack;
import '../processing/host/stack_host.dart' show HostStacks;
import '../processing/transport/transport_behaviours.dart'
    show DirectBeltInputBehaviour, TransportedItemStack;
import '../manifest/manifest.dart';
import '../manifest/registries.g.dart' show kFluids;
import 'drain.dart';
import 'fluid_helper.dart';
import 'fluid_host.dart';
import 'fluid_propagator.dart';
import 'fluid_runtime.dart';
import 'fluid_stack.dart';
import 'fluid_tank.dart';
import 'fluid_world.dart';
import 'flowing_fluid.dart' show FlowingFluidDef, FlowingFluidLogic, placeableFluidDefs;
import 'generic_item_fluid.dart';
import 'hose_pulley_entity.dart';
import 'pipe_block_entities.dart';
import 'pipe_blocks.dart';
import 'pipe_shapes.dart';
import 'pipe_state_logic.dart';
import 'pump_logic.dart';
import 'spout.dart';
import 'tank_placement.dart';
import 'virtual_fluid.dart';

/// `Pos` of a host position.
Pos posOf(BlockPos p) => (p.x, p.y, p.z);

/// The [BState] of [block] at [stateIndex].
BState stateOf(CreateBlock block, int stateIndex) =>
    BState(block.key, block.stateOf(stateIndex));

/// The [FluidWorld] of a host world.
FluidWorld fluidWorldOf(World world) {
  final runtime = FluidsRuntime.instance;
  return runtime.levelOf(runtime.worlds.touch(world))!;
}

/// `Entity.getNearestLookingDirection()` from a player's yaw and pitch.
Direction nearestLooking(Player player) {
  final yaw = player.getYaw() * math.pi / 180;
  final pitch = player.getPitch() * math.pi / 180;
  return Direction.nearest(
    -math.sin(yaw) * math.cos(pitch),
    -math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  );
}

/// `BlockPlaceContext.getNearestLookingDirections()`: all six directions, nearest first.
List<Direction> nearestLookingDirections(Player player) {
  final yaw = player.getYaw() * math.pi / 180;
  final pitch = player.getPitch() * math.pi / 180;
  return Direction.orderedByNearest(
    -math.sin(yaw) * math.cos(pitch),
    -math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  );
}

// -- Pipes -----------------------------------------------------------------------------------

CreateBlock _pipeBlock(
  String key, {
  required String blockEntityType,
  List<PlacementRule> placement = const [],
  bool encased = false,
  bool straight = false,
  bool smart = false,
  bool valve = false,
}) {
  late final CreateBlock block;
  // `FluidPipeBlock.getShape` and friends: the arm/core boxes of the pipe, per state.
  final shapes = pipeShapeSpec('create:$key');
  block = manifestBlock(
    key,
    blockEntityType: blockEntityType,
    placement: placement,
    collisionShape: shapes?.collisionShape,
    selectionShape: shapes?.selectionShape,
    shapeRules: shapes?.shapeRules ?? const [],
    behavior: _pipeBehavior(
      () => block,
      encased: encased,
      straight: straight,
      smart: smart,
      valve: valve,
    ),
  );
  return block;
}

BlockBehavior _pipeBehavior(
  CreateBlock Function() blockRef, {
  required bool encased,
  required bool straight,
  required bool smart,
  required bool valve,
}) {
  BState stateOfEvent(int index) => stateOf(blockRef(), index);

  void propagate(World world, Pos p, BState state) =>
      FluidPropagator.propagateChangedPipe(fluidWorldOf(world), p, state);

  /// `FluidPipeBlock.onPlace`: vanilla calls `onPlace` for every write that leaves the block with
  /// another state, and the pipe schedules its own `tick()` one tick later at `TickPriority.HIGH`.
  /// `tick()` is `propagateChangedPipe`, and its `wipePressure` re-creates the block entity's
  /// connections from the state now in the world; the immediate [propagate] of a hook can run
  /// before that write lands, so the entity (and the client data it publishes) would keep the
  /// connections of the previous state.
  void schedulePropagate(World world, Pos p) => world.scheduleBlockTick(
    pos: p.toBlockPos(),
    delayTicks: 1,
    priority: TickPriority.high,
  );

  Future<BState> place(
    World world,
    Pos p,
    BState state,
    Direction preferred, {
    List<Direction> lookingDirections = const [],
  }) async {
    final level = fluidWorldOf(world);
    if (smart) {
      // `SmartFluidPipeBlock.getStateForPlacement`: the pipe lies along the axis of the pipes it
      // was placed against, and its `facing`/`face` follow that axis.
      final axis = PipeStateLogic.smartPipePreferredAxis(level, p);
      var s = state;
      if (axis == Axis.y) {
        s = s
            .setValue('face', 'wall')
            .setDir('facing', (s.dir('facing') ?? Direction.north).opposite);
      } else if (axis != null) {
        if (s['face'] == 'wall') s = s.setValue('face', 'floor');
        for (final d in lookingDirections) {
          if (d.axis != axis) continue;
          s = s.setDir('facing', d.opposite);
        }
      }
      setFluidBlock(world, p, s);
      schedulePropagate(world, p);
      return s;
    }
    if (straight || encased) return state;
    final updated = PipeStateLogic.updateBlockState(
      state,
      preferred,
      null,
      level,
      p,
    );
    if (updated == state) return updated;
    setFluidBlock(world, p, updated);
    schedulePropagate(world, p);
    return updated;
  }

  return BlockBehavior(
    onPlaced: (server, e) async {
      final world = e.targetWorld;
      final p = posOf(e.pos);
      final state = stateOfEvent(e.stateIndex);
      final playerId = e.player;
      final player = playerId == null
          ? null
          : server.getPlayerByUuid(id: playerId);
      final preferred = player == null
          ? (state.dir('facing') ?? Direction.north)
          : nearestLooking(player);
      final looking = player == null
          ? const <Direction>[]
          : nearestLookingDirections(player);
      final finalState = await place(
        world,
        p,
        state,
        preferred,
        lookingDirections: looking,
      );
      propagate(world, p, finalState);
    },
    onNeighborUpdate: (server, e) {
      final world = e.targetWorld;
      final p = posOf(e.pos);
      final state = stateOfEvent(e.stateIndex);
      final level = fluidWorldOf(world);
      var updated = state;
      if (!encased && !straight && !smart) {
        // `FluidPipeBlock.neighborChanged`: only a neighbour the pipe cares about, on a side it
        // is open to, changes the pipe; the changed side becomes the preferred direction and the
        // opposite side is left alone.
        final changed = FluidPropagator.validateNeighbourChange(
          state,
          level,
          p,
          posOf(e.sourcePos),
        );
        if (changed == null) return;
        if (!PipeBlocks.isOpenAt(state, changed)) return;
        updated = PipeStateLogic.updateBlockState(
          state,
          changed,
          changed.opposite,
          level,
          p,
        );
        if (updated != state) {
          setFluidBlock(world, p, updated);
          schedulePropagate(world, p);
        }
      }
      propagate(world, p, updated);
    },
    // `FluidPipeBlock.updateShape`: a changed neighbour opens or closes the side it is on. The
    // neighbour-change hook alone is not enough: `FluidPropagator.validateNeighbourChange`
    // ignores pipes, axis pipes, pumps and liquids, so without this a pipe placed next to a pipe
    // or a pump would never open towards it.
    onUpdateShape: encased || straight || smart
        ? null
        : (server, e) {
            final world = e.targetWorld;
            final p = posOf(e.pos);
            final state = stateOfEvent(e.stateIndex);
            final direction = e.direction.toDirection();
            final updated = PipeStateLogic.updateBlockState(
              state,
              direction,
              direction.opposite,
              fluidWorldOf(world),
              p,
            );
            if (updated == state) return null;
            // The hook answers with a state *index* of the block, not a state id: the host takes
            // the answer only while it is below the block's state count and then looks the state
            // up as `states[index]` (`dynamic.rs`, `state_id`). A global id (`resolveState`) is
            // always past that count for a plugin block, so the host dropped the answer and the
            // pipe kept the shape it was placed with: it could never bend.
            final index = stateIndexOf(blockRef(), updated);
            if (index != null) schedulePropagate(world, p);
            return index;
          },
    onScheduledTick: (server, e) =>
        propagate(e.targetWorld, posOf(e.pos), stateOfEvent(e.stateIndex)),
    onStateReplaced: (server, e) async {
      final world = e.targetWorld;
      final p = posOf(e.pos);
      propagate(world, p, stateOfEvent(e.oldStateIndex));
      // `FluidPipeBlock.affectNeighborsAfterRemoval`: the bracket comes back.
      await _dropBracket(world, e.pos);
    },
    onUse: smart
        ? (server, e) async {
            final be = FluidsRuntime.instance.store.at(
              FluidsRuntime.instance.worlds.touch(e.targetWorld),
              e.pos,
            );
            if (be is! SmartFluidPipeBlockEntity) return BlockUseResult.pass;
            final pipe = be;
            // `FilteringBehaviour.onShortInteract` needs an item; an empty hand passes.
            if (!e.withItem) return BlockUseResult.pass;
            final key = await e.item.getRegistryKey();
            final bucket = FluidRegistries.fromBucket(key);
            if (bucket != null) {
              pipe.setFilterFluid(bucket.fluid, bucket.data);
            } else {
              // `FilteringBehaviour.forFluids` + `FilterItemStack.test(FluidStack)`: an item with
              // no fluid of its own is a valid filter that matches no fluid at all.
              final handler = e.item.fluidHandler;
              final drained = handler == null
                  ? null
                  : await handler.drain(maxAmount: 1000, simulate: true);
              if (drained == null || drained.amount <= 0) {
                pipe.setFilterMatchesNothing(key);
              } else {
                final filtered = fromHostFluid(drained);
                pipe.setFilterFluid(filtered.fluid, filtered.data);
              }
            }
            pipe.sendData();
            propagate(e.targetWorld, posOf(e.pos), stateOfEvent(e.stateIndex));
            return BlockUseResult.success;
          }
        : null,
    // `EncasedPipeBlock` / `GlassFluidPipeBlock.getCloneItemStack`: the plain pipe.
    onCloneItem: encased || straight
        ? (server, e) =>
              ItemStack.create(registryKey: 'create:fluid_pipe', count: 1)
        : null,
  );
}

/// `FluidPipeBlock.removeBracket`: drops the bracket item of a pipe that is removed.
Future<void> _dropBracket(World world, BlockPos pos) async {
  final runtime = FluidsRuntime.instance;
  final worldId = runtime.worlds.touch(world);
  final bracket = runtime.store
      .at(worldId, pos)
      ?.getBehaviour<BracketedBlockEntityBehaviour>();
  final removed = await bracket?.removeBracket(inOnReplacedContext: true);
  if (removed == null) return;
  final stack = await HostStacks.write(PStack(removed.key, 1));
  if (stack != null) {
    await world.dropItem((pos.x + .5, pos.y + .5, pos.z + .5), stack);
  }
}

// -- Tanks -----------------------------------------------------------------------------------

CreateBlock _tankBlock(
  String key, {
  required String blockEntityType,
  required bool creative,
}) {
  late final CreateBlock block;
  final itemData = tankItemDataBlock(key, blockEntityType);
  ItemDataStamps.register(itemData);
  block = manifestBlock(
    key,
    blockEntityType: blockEntityType,
    behavior: BlockBehavior(
      onPlaced: (server, e) async {
        final be = FluidsRuntime.instance.store.at(
          FluidsRuntime.instance.worlds.touch(e.targetWorld),
          e.pos,
        );
        if (be is FluidTankBlockEntity) be.updateConnectivityNow();
        // `FluidTankBlock.onPlace` forms the multiblock first; vanilla merges the item's block
        // entity data onto the fresh entity afterwards (`BlockItem.place`).
        await ItemDataStamps.applyPlaced(itemData, server, e);
        await _tryTankMultiPlace(server, e, block, blockEntityType);
      },
      // `getCloneItemStack` with the tank's data on it (vanilla's `addBlockDataToItem`); the
      // placement sanitises it again (`FluidTankItem.place`).
      onCloneItem: (server, e) => ItemDataStamps.cloneItem(itemData, e),
      onNeighborUpdate: (server, e) {
        // `updateShape`: a change below refreshes the boiler temperature; a steam engine or
        // whistle next to the tank changes the boiler itself.
        final world = e.targetWorld;
        final p = posOf(e.pos);
        final stateBelow = fluidWorldOf(world).stateAt(p.below);
        final be = FluidsRuntime.instance.store.at(
          FluidsRuntime.instance.worlds.touch(world),
          e.pos,
        );
        if (be is! FluidTankBlockEntity) return;
        if (!PipeBlocks.isTank(stateBelow)) be.updateBoilerTemperature();
        be.controllerBe?.updateBoilerState();
      },
      onStateReplaced: (server, e) {
        final be = FluidsRuntime.instance.store.at(
          FluidsRuntime.instance.worlds.touch(e.targetWorld),
          e.pos,
        );
        if (be is FluidTankBlockEntity) be.updateConnectivityNow();
      },
      onComparatorOutput: (server, e) {
        final be = FluidsRuntime.instance.store.at(
          FluidsRuntime.instance.worlds.touch(e.targetWorld),
          e.pos,
        );
        if (be is! FluidTankBlockEntity) return null;
        final controller = be.controllerBe;
        if (controller == null) return 0;
        return fractionToRedstoneLevel(controller.fillState);
      },
      onUse: (server, e) => _tankUse(creative, e),
    ),
  );
  return block;
}

// -- The tank's item data (break -> place) ----------------------------------------------------

/// The item data of the tank blocks: the block entity's saved NBT in the vanilla
/// `minecraft:block_entity_data` component.
///
/// The data is written raw on drop and on pick-block (Java's `addBlockDataToItem`) and
/// sanitised again on placement, exactly as `FluidTankItem.place` does.
ItemDataBlock tankItemDataBlock(String blockKey, String blockEntityType) => ItemDataBlock(
  blockKey: 'create:$blockKey',
  itemKey: manifestItemKeyOf(blockKey),
  componentKey: blockEntityDataComponent,
  entityAt: (world, pos) {
    final runtime = FluidsRuntime.instance;
    final be = runtime.store.at(runtime.worlds.touch(world), pos);
    // A creative tank is a `FluidTankBlockEntity` too, so the type of the block decides.
    return be is FluidTankBlockEntity && be.typeKey == blockEntityType ? be : null;
  },
  itemComponent: _tankSavedNbtComponent,
  applyComponent: _applyTankItemData,
);

/// The tank's own saved NBT as the item component (`ServerGamePacketListenerImpl
/// .addBlockDataToItem` writes what `saveCustomOnly` produces).
List<int> _tankSavedNbtComponent(CreateBlockEntity be) =>
    BlockEntityItemData.encodeBlockEntityData(_tankSavedNbt(be));

Map<String, NbtValue> _tankSavedNbt(CreateBlockEntity be) {
  final tag = NbtCompound();
  be.write(tag, clientPacket: false);
  return valueOfCompound(tag).asCompound;
}

/// `FluidTankItem.place` + `TypedEntityData.loadInto`: the item's data with the multiblock keys
/// gone and the contents clamped, merged *over* the fresh tank's own saved NBT and read back.
///
/// Merging over the fresh entity's NBT is what keeps the contents: the item has no `Size`/
/// `Height` (they were stripped), so the fresh single tank's own `1`/`1` survive, its capacity is
/// one block's, and the clamped `TankContent` fits instead of being drained away.
void _applyTankItemData(CreateBlockEntity be, List<int>? bytes) {
  if (bytes == null) return;
  final itemData = BlockEntityItemData.decodeBlockEntityData(bytes);
  if (itemData == null) return;
  final merged = BlockEntityItemData.merge(
    _tankSavedNbt(be),
    BlockEntityItemData.sanitiseTankItemData(
      itemData,
      capacityMultiplier: FluidTankBlockEntity.capacityMultiplier,
    ),
  );
  be.read(compoundOf(NbtValue.compound(merged)), clientPacket: false);
}

/// `ComparatorUtil.fractionToRedstoneLevel`.
int fractionToRedstoneLevel(double fraction) {
  if (fraction <= 0) return 0;
  return math.min(15, (fraction * 14).floor() + 1);
}

/// Writes [spec] to the hand of [player] (`Player.setItemInHand`); an empty spec clears it.
Future<void> _setHand(Player player, Hand hand, FluidItemSpec spec) async {
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

/// `FluidTankBlock.useItemOn`: moves fluid between the held item and the tank. Like Java, a
/// regular tank only accepts a hand interaction from a creative player; a creative tank works for
/// everyone and copies the fluid it is given.
Future<BlockUseResult> _tankUse(
  bool creative,
  CustomBlockUseEventData e,
) async {
  if (!e.withItem) return BlockUseResult.tryEmptyHand;
  final player = e.player;
  // The use event is the only one that carries the hand, and the placement event that follows it
  // has no hand at all (`FluidTankItem` reads `ctx.getItemInHand()`, the hand of the click), so
  // the hand of this click is remembered for `_tryTankMultiPlace`.
  final id = player.getId();
  _tankUseHand[(id.high, id.low)] = e.hand;
  if (!player.isCreative && !creative) return BlockUseResult.tryEmptyHand;

  final runtime = FluidsRuntime.instance;
  final worldId = runtime.worlds.touch(e.targetWorld);
  final be = runtime.store.at(worldId, e.pos);
  if (be is! FluidTankBlockEntity) return BlockUseResult.pass;
  final controller = be.controllerBe;
  final storage = controller?.fluidHandler ?? be.fluidHandler;
  if (storage == null) return BlockUseResult.tryEmptyHand;

  final inventory = player.getInventory();
  final items = inventory.asInventory();
  final slot = inventory.getSelectedSlot();
  final stack = items.getItem(slot: slot);
  if (stack == null) return BlockUseResult.tryEmptyHand;

  final itemKey = await stack.getRegistryKey();
  final count = await stack.getCount();
  if (count <= 0) return BlockUseResult.tryEmptyHand;
  final item = FluidItemSpec(itemKey, count, await fluidItemComponents(stack));
  final emptying = GenericItemEmptying(runtime.rules, runtime.recipes);
  final filling = GenericItemFilling(runtime.rules);
  final previous = storage.fluidInTank(0);

  var exchanged = false;
  var toItem = false;

  // `FluidHelper.tryEmptyItemIntoBE`.
  if (emptying.canItemBeEmptied(item)) {
    final (fluid, _, _) = emptying.emptyItem(item, simulate: true);
    if (fluid.isNotEmpty &&
        storage.fill(fluid, simulate: true) == fluid.amount) {
      final (emptied, remainder, newStack) =
          emptying.emptyItem(item, simulate: false);
      storage.fill(emptied, simulate: false);
      // The held item is consumed: the last item of the stack becomes its container in the
      // hand, an item of a bigger stack leaves the container in the inventory.
      if (!player.isCreative && be is! CreativeFluidTankBlockEntity) {
        if (newStack.isEmpty) {
          await _setHand(player, e.hand, remainder);
        } else {
          await _setHand(player, e.hand, newStack);
          final back = await HostStacks.write(
            PStack(remainder.key, remainder.count, comps: remainder.comps),
          );
          if (back != null) await items.give(back);
        }
      }
      if (creative &&
          be is CreativeFluidTankBlockEntity &&
          emptied.isNotEmpty) {
        be.setContainedFluid(emptied);
      }
      exchanged = true;
    }
  }

  // `FluidHelper.tryFillItemFromBE`.
  if (!exchanged && filling.canItemBeFilled(item)) {
    for (var i = 0; i < storage.tanks; i++) {
      final fluid = storage.fluidInTank(i);
      if (fluid.isEmpty) continue;
      final required = filling.getRequiredAmountForItem(
        item.withCount(1),
        fluid,
      );
      if (required == -1 || required > fluid.amount) continue;
      final (result, remaining, _) = filling.fillItem(required, item, fluid);
      if (result.isEmpty) continue;
      storage.drainFluid(fluid.withAmount(required), simulate: false);
      // `FluidHelper.tryFillItemFromBE`: a creative player, and any player at a creative tank,
      // works on a copy, so the hand keeps its item; only a survival player at a regular tank
      // consumes one. The filled container goes back to the inventory unless the player is
      // creative (a creative tank still gives it back to everyone).
      if (!player.isCreative) {
        if (be is! CreativeFluidTankBlockEntity) {
          await _setHand(player, e.hand, remaining);
        }
        final out = await HostStacks.write(
          PStack(result.key, result.count, comps: result.comps),
        );
        if (out != null) await items.give(out);
      }
      if (creative && be is CreativeFluidTankBlockEntity) {
        be.setContainedFluid(FStack.empty);
      }
      exchanged = true;
      toItem = true;
      break;
    }
  }

  if (!exchanged) {
    // A recognised item is consumed without an exchange (`InteractionResult.SUCCESS`).
    if (emptying.canItemBeEmptied(item) || filling.canItemBeFilled(item)) {
      return BlockUseResult.success;
    }
    return BlockUseResult.tryEmptyHand;
  }

  final fluidInTank = storage.fluidInTank(0);
  final sound = toItem
      ? FluidHelper.getFillSound(previous)
      : FluidHelper.getEmptySound(fluidInTank);
  final capacity = FluidTankBlockEntity.capacityMultiplier * 16;
  var pitch = capacity == 0
      ? 0.5
      : (1 - fluidInTank.amount / capacity).clamp(0.0, 1.0);
  pitch /= 1.5;
  pitch += .5;
  pitch += (runtime.random.nextDouble() - .5) / 4;
  runtime
      .levelOf(worldId)
      ?.playSound((e.pos.x, e.pos.y, e.pos.z), sound, volume: .5, pitch: pitch);

  if (!fluidInTank.isSameFluid(previous)) {
    controller?.sendDataImmediately();
    controller?.markDirty();
  }
  return BlockUseResult.success;
}

/// `FluidTankItem.tryMultiPlace`: placing a tank on the top or bottom of a wider
/// tank places the rest of that row.
///
/// The writes below go through the host, which fires `placed` again for each of them; those must
/// not start a layer of their own. Java needs no such guard because every `super.place` of the
/// loop returns before the next one, so this is a set of the positions being written rather than
/// a global flag: another player placing a tank in the same tick still gets their own layer.
final Set<Pos> _tankLayerWrites = {};

/// The hand of the last item-use on a tank block, by player (see `_tankUse`).
final Map<(int, int), Hand> _tankUseHand = {};

/// Takes [count] items of [itemKey] out of the hand [playerId] placed with, one tick after the
/// placement.
///
/// The count cannot be written while the placement runs: `handle_use_item_on` syncs the hand from
/// the stack it snapshotted before the placement
/// (`crates/pumpkin-core/src/net/java/play/use_item_on.rs` `set_stack_in_hand(hand, after)`), which
/// throws the write away. The symmetry wand's mirrored placement defers its work the same way.
Future<void> _consumeHeld(
  Server server,
  Uuid playerId,
  Hand hand,
  String itemKey,
  int count,
) async {
  final player = server.getPlayerByUuid(id: playerId);
  if (player == null) return;
  final held = player.getItemInHand(hand: hand);
  if (held == null || await held.getRegistryKey() != itemKey) return;
  final current = await held.getCount();
  if (current <= 0) return;
  // The hand may have changed under us (a drop or a slot swap in that one tick): never take more
  // than is there.
  final take = current < count ? current : count;
  if (current - take <= 0) {
    await player.setItemInHand(hand: hand, stack: null);
  } else {
    await held.setCount(count: current - take);
    await player.setItemInHand(hand: hand, stack: held);
  }
}

/// `SymmetryWandItem.presentInHotbar`: a wand mirrors the placement itself, so the tank must not
/// expand a layer as well (`FluidTankItem.java:72`).
Future<bool> _hasSymmetryWand(Player player) async {
  final items = player.getInventory().asInventory();
  for (var slot = 0; slot < 9; slot++) {
    final stack = items.getItem(slot: slot);
    if (stack != null &&
        await stack.getRegistryKey() == 'create:wand_of_symmetry') {
      return true;
    }
  }
  return false;
}

Future<void> _tryTankMultiPlace(
  Server server,
  CustomBlockPlacedEventData e,
  CreateBlock block,
  String typeKey,
) async {
  final pos = posOf(e.pos);
  if (_tankLayerWrites.contains(pos)) return;
  final playerId = e.player;
  if (playerId == null) return;
  final player = server.getPlayerByUuid(id: playerId);
  if (player == null || player.asEntity().isSneaking()) return;
  if (await _hasSymmetryWand(player)) return;

  final runtime = FluidsRuntime.instance;
  final world = e.targetWorld;
  final worldId = runtime.worlds.touch(world);

  // `ConnectivityHandler.partAt(type, level, pos).getControllerBE()`: the multiblock a tank
  // belongs to, when it is one of the item's own tank type (a regular tank does not extend a
  // creative one).
  TankExtent? extentAt(Pos p) {
    final be = runtime.store.at(
      worldId,
      BlockPos(x: p.$1, y: p.$2, z: p.$3),
    );
    if (be is! FluidTankBlockEntity || be.typeKey != typeKey) return null;
    final controller = be.controllerBe;
    if (controller == null) return null;
    return (
      controller: controller.partPos,
      width: controller.width,
      height: controller.height,
    );
  }

  final level = fluidWorldOf(world);
  final targets = tankLayerTargets(
    pos: pos,
    below: extentAt(pos.below),
    above: extentAt(pos.above),
    isTank: (p) => PipeBlocks.isTank(level.stateAt(p)),
    canBeReplaced: level.canBeReplaced,
  );
  if (targets == null || targets.isEmpty) return;

  // Java reads the stack it was placed with (`ctx.getItemInHand()`, the hand of the click); the
  // placement event carries no hand, so the one the use event recorded stands in.
  final hand = _tankUseHand.remove((playerId.high, playerId.low)) ?? Hand.right;
  final held = player.getItemInHand(hand: hand);
  final itemKey = held == null ? null : await held.getRegistryKey();
  if (!player.isCreative) {
    // `if (!player.isCreative() && stack.getCount() < tanksToPlace) return;`
    // (`FluidTankItem.java:121`): Java reads the stack *after* its own `super.place` spent the
    // tank of the clicked block, so one item is already gone.
    final count = held == null ? 0 : await held.getCount();
    if (count - 1 < targets.length) return;
  }

  final state = BState(block.key, block.definition.defaultState);
  final stateId = BlockRegistry.resolveState(state.key, state.props);
  if (stateId == null) return;

  _tankLayerWrites.addAll(targets);
  try {
    for (final p in targets) {
      final bp = BlockPos(x: p.$1, y: p.$2, z: p.$3);
      await world.setBlockState(
        pos: bp,
        state: stateId,
        updateFlags: BlockUpdateFlags.normal,
      );
      runtime.store.createAt(world, bp, typeKey);
    }
    for (final p in targets) {
      final be = runtime.store.at(worldId, BlockPos(x: p.$1, y: p.$2, z: p.$3));
      if (be is FluidTankBlockEntity) be.updateConnectivityNow();
    }
  } finally {
    _tankLayerWrites.removeAll(targets);
  }

  // One tank per placed block (`FluidTankItem.java:114-122` spends one `super.place` and one item
  // on each, after the clicked block's own placement and item). The host has spent the clicked
  // block's tank by the time this tick ends, so the rest are taken next tick.
  if (!player.isCreative && itemKey != null) {
    server.runLater(
      1,
      (s) => _consumeHeld(s, playerId, hand, itemKey, targets.length),
    );
  }
}

// -- Spout, drain, hose pulley ---------------------------------------------------------------

CreateBlock _spoutBlock() {
  late final CreateBlock block;
  block = manifestBlock(
    'spout',
    blockEntityType: 'create:spout',
    behavior: BlockBehavior(onComparatorOutput: (server, e) => _tankLevelOf(e)),
  );
  return block;
}

CreateBlock _drainBlock() {
  late final CreateBlock block;
  block = manifestBlock(
    'item_drain',
    blockEntityType: 'create:item_drain',
    behavior: BlockBehavior(
      onComparatorOutput: (server, e) => _tankLevelOf(e),
      onUse: (server, e) => _drainUse(e),
      onLandedUpon: (server, e) async {
        await _drainLanded(e);
        return e.damageMultiplier;
      },
    ),
  );
  return block;
}

int? _tankLevelOf(CustomBlockComparatorOutputEventData e) {
  final be = FluidsRuntime.instance.store.at(
    FluidsRuntime.instance.worlds.touch(e.targetWorld),
    e.pos,
  );
  if (be is! FluidCapable) return null;
  final tank = (be as FluidCapable).fluidHandler;
  if (tank == null) return null;
  final capacity = tank.tankCapacity(0);
  if (capacity <= 0) return 0;
  return fractionToRedstoneLevel(tank.fluidInTank(0).amount / capacity);
}

/// `ItemDrainBlock.useItemOn`: empties a held item, or gives the held item back.
Future<BlockUseResult> _drainUse(CustomBlockUseEventData e) async {
  final worldId = FluidsRuntime.instance.worlds.touch(e.targetWorld);
  final be = FluidsRuntime.instance.store.at(worldId, e.pos);
  if (be is! ItemDrainBlockEntity) return BlockUseResult.pass;

  if (e.withItem) {
    final inventory = e.player.getInventory();
    final items = inventory.asInventory();
    final slot = inventory.getSelectedSlot();
    final stack = items.getItem(slot: slot);
    if (stack != null) {
      final key = await stack.getRegistryKey();
      // `ItemDrainBlock.useItemOn`: a block item without a fluid handler is left to the
      // vanilla placement, so the drain does not swallow it.
      if (BlockRegistry.resolveState(key) != null &&
          stack.fluidHandler == null) {
        return BlockUseResult.tryEmptyHand;
      }
      final count = await stack.getCount();
      final item = FluidItemSpec(key, count, await fluidItemComponents(stack));
      final emptying = GenericItemEmptying(
        FluidsRuntime.instance.rules,
        FluidsRuntime.instance.recipes,
      );
      if (emptying.canItemBeEmptied(item.withCount(1))) {
        final (fluid, remainder, _) = emptying.emptyItem(
          item.withCount(1),
          simulate: true,
        );
        if (be.insertFluid(fluid, simulate: true)) {
          be.insertFluid(fluid, simulate: false);
          if (count <= 1) {
            await items.setItem(slot: slot, item: null);
          } else {
            await stack.setCount(count: count - 1);
            await items.setItem(slot: slot, item: stack);
          }
          if (remainder.isNotEmpty) {
            final remainderStack = await HostStacks.write(
              PStack(remainder.key, remainder.count, comps: remainder.comps),
            );
            if (remainderStack != null) await items.give(remainderStack);
          }
          be.sendData();
          return BlockUseResult.success;
        }
      }
    }
  }

  final held = be.heldItemStack;
  if (held.isNotEmpty) {
    final stack = await HostStacks.write(held);
    if (stack != null) await e.player.getInventory().asInventory().give(stack);
    be.heldItem = null;
    be.sendData();
  }
  // `ItemDrainBlock.useItemOn` consumes a held-item click; the empty hand goes on to
  // vanilla (`useWithoutItem` passes).
  return e.withItem ? BlockUseResult.success : BlockUseResult.tryEmptyHand;
}

/// `ItemDrainBlock.fallOn`: a dropped item landing on the drain is handed to its belt input.
Future<void> _drainLanded(CustomBlockLandedEventData e) async {
  final world = e.targetWorld;
  final entity = world.getEntityById(id: e.entityId);
  if (entity == null) return;
  final item = entity.asItem();
  if (item == null) return;

  final p = entity.getPosition();
  final blockPos = BlockPos(x: p.$1.floor(), y: p.$2.floor(), z: p.$3.floor());
  final be = FluidsRuntime.instance.store.at(
    FluidsRuntime.instance.worlds.touch(world),
    blockPos,
  );
  final input = be?.getBehaviour<DirectBeltInputBehaviour>();
  if (input == null) return;

  final velocity = entity.getVelocity();
  final length = math.sqrt(
    velocity.$1 * velocity.$1 + velocity.$3 * velocity.$3,
  );
  if (length < 1e-4) return;
  final nearest = Direction.nearest(
    velocity.$1 / length,
    0,
    velocity.$3 / length,
  );

  final stack = await HostStacks.read(item.getStack());
  if (stack.isEmpty) return;
  final remainder = input.handleInsertion(
    TransportedItemStack(stack),
    nearest.serializedName,
    false,
  );
  if (remainder.isEmpty) {
    item.discard();
  } else if (remainder.count != stack.count) {
    final out = await HostStacks.write(remainder);
    if (out != null) await item.setStack(stack: out);
  }
}

// -- Block entity types ----------------------------------------------------------------------

List<BlockEntityTypeSpec> buildFluidBlockEntityTypes() => [
  BlockEntityTypeSpec(
    key: 'create:fluid_pipe',
    validBlocks: ['create:fluid_pipe'],
    create: FluidPipeBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:encased_fluid_pipe',
    validBlocks: ['create:encased_fluid_pipe'],
    create: FluidPipeBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:glass_fluid_pipe',
    validBlocks: ['create:glass_fluid_pipe'],
    create: StraightPipeBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:smart_fluid_pipe',
    validBlocks: ['create:smart_fluid_pipe'],
    create: SmartFluidPipeBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:fluid_valve',
    validBlocks: ['create:fluid_valve'],
    create: FluidValveBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:mechanical_pump',
    validBlocks: ['create:mechanical_pump'],
    create: PumpBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:fluid_tank',
    validBlocks: ['create:fluid_tank'],
    create: FluidTankBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:creative_fluid_tank',
    validBlocks: ['create:creative_fluid_tank'],
    create: CreativeFluidTankBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:spout',
    validBlocks: ['create:spout'],
    create: SpoutBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:item_drain',
    validBlocks: ['create:item_drain'],
    create: ItemDrainBlockEntity.new,
  ),
  BlockEntityTypeSpec(
    key: 'create:hose_pulley',
    validBlocks: ['create:hose_pulley'],
    create: HosePulleyBlockEntity.new,
  ),
];

// -- Blocks ----------------------------------------------------------------------------------

/// The behaviour of a `LiquidBlock` that holds a fluid the host has no flow physics for.
///
/// Vanilla runs the fluid from fluid ticks (`LiquidBlock.onPlace`/`neighborChanged` schedule
/// them, `FlowingFluid.tick` re-schedules itself). `World::schedule_fluid_tick` only ever
/// reaches `FlowingWater`/`FlowingLava` (`pumpkin-core/src/world/mod.rs:2095-2108`), so a fluid
/// tick for honey or chocolate goes nowhere: the block schedules a block tick of its own at
/// [FlowingFluidDef.tickRate] instead, and runs [FlowingFluidLogic.tick] there
/// (`FluidHostWorld` maps the logic's own re-scheduling onto the same hook).
BlockBehavior liquidBlockBehavior(FlowingFluidDef def) {
  void schedule(World world, BlockPos pos) {
    if (world.hasScheduledTick(pos: pos)) return;
    world.scheduleBlockTick(
      pos: pos,
      delayTicks: def.tickRate.clamp(1, 255),
      priority: TickPriority.high,
    );
  }

  return BlockBehavior(
    // `LiquidBlock.onPlace`: the fluid tick Java schedules from the placement.
    onPlaced: (server, e) => schedule(e.targetWorld, e.pos),
    // `LiquidBlock.neighborChanged`: a neighbour change always re-schedules the fluid tick.
    onNeighborUpdate: (server, e) => schedule(e.targetWorld, e.pos),
    onScheduledTick: (server, e) =>
        FlowingFluidLogic(def, fluidWorldOf(e.targetWorld)).tick(posOf(e.pos)),
  );
}

/// The non-kinetic fluid blocks (the kinetic ones are built by the module, which
/// needs the kinetic service).
List<CreateBlock> buildFluidBlocks() => [
  _pipeBlock(
    'fluid_pipe',
    blockEntityType: 'create:fluid_pipe',
    placement: [PlacementRule.inWater('waterlogged')],
  ),
  _pipeBlock(
    'encased_fluid_pipe',
    blockEntityType: 'create:encased_fluid_pipe',
    encased: true,
  ),
  _pipeBlock(
    'glass_fluid_pipe',
    blockEntityType: 'create:glass_fluid_pipe',
    straight: true,
    placement: [
      PlacementRule.clickedAxis('axis'),
      PlacementRule.inWater('waterlogged'),
    ],
  ),
  _pipeBlock(
    'smart_fluid_pipe',
    blockEntityType: 'create:smart_fluid_pipe',
    smart: true,
    placement: [
      // `FaceAttachedHorizontalDirectionalBlock`: `facing` is horizontal only.
      PlacementRule.horizontalFacing('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
  ),
  _tankBlock(
    'fluid_tank',
    blockEntityType: 'create:fluid_tank',
    creative: false,
  ),
  _tankBlock(
    'creative_fluid_tank',
    blockEntityType: 'create:creative_fluid_tank',
    creative: true,
  ),
  _spoutBlock(),
  _drainBlock(),
  manifestBlock('honey', behavior: liquidBlockBehavior(placeableFluidDefs['create:honey']!), drops: BlockDrops.nothing),
  manifestBlock(
    'chocolate',
    behavior: liquidBlockBehavior(placeableFluidDefs['create:chocolate']!),
    drops: BlockDrops.nothing,
  ),
];

// -- Kinetic blocks --------------------------------------------------------------------------

/// `PumpBlock`: the mechanical pump.
CreateBlock pumpBlock() {
  late final CreateBlock block;
  final shapes = pipeShapeSpec(PipeKeys.pump);
  block = manifestBlock(
    'mechanical_pump',
    blockEntityType: 'create:mechanical_pump',
    placement: [
      // `DirectionalKineticBlock.getStateForPlacement`: a neighbouring shaft decides the facing,
      // unless the player sneaks.
      PlacementRule.neighbourShaft(
        'facing',
        bearingShaftNeighbours,
        opposite: true,
        whenSneaking: false,
      ),
      PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
      PlacementRule.lookingDirection('facing', whenSneaking: true),
      PlacementRule.inWater('waterlogged'),
    ],
    collisionShape: shapes?.collisionShape,
    selectionShape: shapes?.selectionShape,
    shapeRules: shapes?.shapeRules ?? const [],
    behavior: buildKineticBehavior(
      () => block,
      neighbor: (c, e) => _kineticNeighbour(c, e),
      scheduledTick: (c) => _propagateKinetic(c),
      replaced: (c, e) => _propagateKinetic(c),
      afterPlaced: (c, e) {
        final playerId = e.player;
        final player = playerId == null
            ? null
            : c.server.getPlayerByUuid(id: playerId);
        var state = c.state;
        if (player != null) {
          // `PumpBlock.getStateForPlacement`: prefer the pipe next to it when that lies on
          // another axis than the one the player looks along.
          final preferred = PipeStateLogic.pumpPreferredFacing(
            fluidWorldOf(c.world),
            kposOf(c),
            nearestLooking(player),
            player.asEntity().isSneaking(),
          );
          if (preferred != null) {
            state = state.set('facing', preferred.serializedName);
            unawaited(c.setState(state));
          }
        }
        // `PumpBlock.onPlace` schedules a tick whenever the state changes, and the
        // tick propagates the pipe network: a wrench flip (no player) must re-route
        // the pressure too. The facing decides the open sides.
        _propagateKineticState(c, state);
      },
    ),
  );
  return block;
}

/// The wrench handler of the mechanical pump.
void registerPumpWrench(WrenchRegistry wrench) {
  wrench.register(
    'create:mechanical_pump',
    CallbackWrenchable(
      rotatedState: (c) {
        final rotated = pumpWrenchState(BState(c.blockKey, c.properties));
        return BlockStates.withProperties(c.blockKey, rotated.props);
      },
    ),
  );
}

/// `FluidValveBlock`: the kinetic valve.
CreateBlock valveBlock() {
  late final CreateBlock block;
  // `FluidValveBlock.getShape`: `AllShapes.FLUID_VALVE` along the axis the valve gates.
  final shapes = pipeShapeSpec(PipeKeys.valve);
  block = manifestBlock(
    'fluid_valve',
    blockEntityType: 'create:fluid_valve',
    placement: [
      // `DirectionalAxisKineticBlock` (via `DirectionalKineticBlock`): a neighbouring shaft
      // decides the facing, unless the player sneaks.
      PlacementRule.neighbourShaft(
        'facing',
        bearingShaftNeighbours,
        opposite: true,
        whenSneaking: false,
      ),
      PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
      PlacementRule.lookingDirection('facing', whenSneaking: true),
      PlacementRule.inWater('waterlogged'),
    ],
    collisionShape: shapes?.collisionShape,
    selectionShape: shapes?.selectionShape,
    shapeRules: shapes?.shapeRules ?? const [],
    behavior: buildKineticBehavior(
      () => block,
      neighbor: (c, e) => _kineticNeighbour(c, e),
      scheduledTick: (c) => _propagateKinetic(c),
      replaced: (c, e) => _propagateKinetic(c),
      afterPlaced: (c, e) {
        // `FluidValveBlock.getStateForPlacement` (`DirectionalAxisKineticBlock`): pick the
        // `axis_along_first` that lets the valve gate the pipe it was placed on.
        final playerId = e.player;
        final player = playerId == null
            ? null
            : c.server.getPlayerByUuid(id: playerId);
        var state = c.state;
        if (player != null) {
          // `Entity.getHorizontalDirection()`.
          final look = Direction.fromYRot(player.getYaw());
          final facing = toFluidDir(c.state.dirOf('facing') ?? Dir.north);
          final alongFirst = PipeStateLogic.valveAxisAlignmentForPlacement(
            facing,
            look,
            shaftTowards: (side) {
              final p = kposOf(c);
              final neighbour = p.relative(side);
              return fluidWorldOf(
                c.world,
              ).hasShaftTowards(neighbour, side.opposite);
            },
            // `FluidValveBlock.prefersConnectionTo(..., shaftAxis: false)`: does the block on that
            // side accept a fluid pipe connection, i.e. is the valve being placed on a pipe run?
            pipeTowards: (side) {
              final world = fluidWorldOf(c.world);
              final neighbour = kposOf(c).relative(side);
              return PipeStateLogic.canConnectTo(
                world,
                neighbour,
                world.stateAt(neighbour),
                side,
              );
            },
          );
          if (state.flag('axis_along_first') != alongFirst) {
            state = state.setFlag('axis_along_first', alongFirst);
            unawaited(c.setState(state));
          }
        }
        // The axis decides the open sides, so propagate the state just placed.
        _propagateKineticState(c, state);
      },
    ),
  );
  return block;
}

/// `HosePulleyBlock`: the kinetic hose pulley.
CreateBlock hosePulleyBlock() {
  late final CreateBlock block;
  block = manifestBlock(
    'hose_pulley',
    blockEntityType: 'create:hose_pulley',
    placement: [PlacementRule.horizontalFacing('facing', opposite: true)],
    behavior: buildKineticBehavior(
      () => block,
      afterPlaced: (c, e) {
        // `HosePulleyBlock.getStateForPlacement`: the pipe is on
        // `HORIZONTAL_FACING.getCounterClockWise()`, so the facing is the
        // counter-clockwise neighbour of the preferred (pipe) side.
        final preferred = PipeStateLogic.hosePulleyPreferredSide(
          fluidWorldOf(c.world),
          kposOf(c),
        );
        if (preferred == null) return;
        final facing = preferred.counterClockWise;
        if (facing.isHorizontal) {
          unawaited(c.setState(c.state.set('facing', facing.serializedName)));
        }
      },
    ),
  );
  return block;
}

/// The position of a kinetic hook as a fluid [Pos].
Pos kposOf(HookCtx c) => (c.kpos.x, c.kpos.y, c.kpos.z);

/// The block state of a kinetic state as the fluid logic sees it.
extension KStateToBState on KState {
  BState get bState => BState(block, props);
}

void _propagateKinetic(HookCtx c) => _propagateKineticState(c, c.state);

void _propagateKineticState(HookCtx c, KState state) =>
    FluidPropagator.propagateChangedPipe(
      fluidWorldOf(c.world),
      kposOf(c),
      state.bState,
    );

void _kineticNeighbour(HookCtx c, CustomBlockNeighborUpdateEventData e) {
  final world = fluidWorldOf(c.world);
  final p = kposOf(c);
  for (final d in Direction.values) {
    final other = p.relative(d);
    final side = FluidPropagator.validateNeighbourChange(
      c.state.bState,
      world,
      p,
      other,
    );
    if (side == null) continue;
    if (!PipeBlocks.isOpenAt(c.state.bState, side)) continue;
    _propagateKinetic(c);
    return;
  }
}

/// `KineticBlockDef` of the hose pulley: it rotates around its horizontal facing.
class HosePulleyDef extends KineticBlockDef {
  const HosePulleyDef();

  @override
  KAxis rotationAxis(KState state) => _axis(state);

  @override
  bool hasShaftTowards(KState state, Dir face) {
    final facing = state.dirOf('facing') ?? Dir.north;
    return face == facing.clockWise(KAxis.y);
  }

  KAxis _axis(KState state) {
    final facing = state.dirOf('facing') ?? Dir.north;
    return facing.clockWise(KAxis.y).axis;
  }
}

/// The kinetic defs the module registers in `onLoad`.
const Map<String, KineticBlockDef> fluidKineticDefs = {
  'create:mechanical_pump': PumpDef(),
  'create:fluid_valve': DirectionalAxisBlockDef(),
  'create:hose_pulley': HosePulleyDef(),
};

// -- Items and fluids ------------------------------------------------------------------------

/// The fluid bucket items (the block items come with the blocks).
const List<String> fluidBucketItems = [
  'create:honey_bucket',
  'create:chocolate_bucket',
];

/// Registers the fluid bucket items.
void registerFluidItems(CreateRegistry registry) {
  for (final key in fluidBucketItems) {
    registry.item(ItemRegistration(key: key, maxStackSize: 1));
  }
}

/// Registers the fluids of the manifest. The canonical order later numbers the
/// still fluid before its flowing variant (Java's order); the host links the two
/// once registration closes, so the insertion order here does not matter.
void registerFluids(CreateRegistry registry) {
  for (final def in kFluids) {
    final still = 'create:${def.sourceKey}';
    final flowing = 'create:${def.flowingKey}';
    final attributes = def.attributes;
    final density = int.tryParse(attributes['density'] ?? '') ?? 1000;
    final viscosity = int.tryParse(attributes['viscosity'] ?? '') ?? 1000;
    // `FluidBuilder.fluidProperties`: honey and chocolate are extracted with
    // `levelDecreasePerBlock: 2, tickRate: 25, slopeFindDistance: 3`; water-like fluids fall back
    // to the vanilla defaults the manifest repeats as `defaultsForUnlisted`. Both variants carry
    // them: Java builds source and flowing from one shared `BaseFlowingFluid.Properties`
    // (`AllFluids.java:61-105`).
    final tickRate = int.tryParse(attributes['tickRate'] ?? '') ?? 5;
    final levelDecreasePerBlock = int.tryParse(attributes['levelDecreasePerBlock'] ?? '') ?? 1;
    final slopeFindDistance = int.tryParse(attributes['slopeFindDistance'] ?? '') ?? 4;
    final tags = switch (def.key) {
      'honey' => const ['c:honey'],
      'chocolate' => const ['c:chocolate'],
      'tea' => const ['c:tea'],
      _ => const <String>[],
    };

    if (def.kind == 'virtual') {
      // `VirtualFluid`: no block, no bucket (potion, tea).
      final virtual = VirtualFluid(still: still, flowing: flowing, tags: tags);
      registry.fluid(virtual.flowingSpec());
      registry.fluid(virtual.stillSpec());
      continue;
    }

    final block = def.blockKey == null ? null : 'create:${def.blockKey}';

    // The flowing variant is virtual: the host's flowing placement needs a
    // `falling` property the manifest liquid blocks do not have.
    registry.fluid(
      FluidSpec(
        key: flowing,
        tickRate: tickRate,
        levelDecreasePerBlock: levelDecreasePerBlock,
        slopeFindDistance: slopeFindDistance,
        density: density,
        viscosity: viscosity,
      ),
    );
    registry.fluid(
      FluidSpec(
        key: still,
        flowingVariant: flowing,
        placement: block == null
            ? null
            : FluidPlacement(block: block, flowing: false),
        bucketItem: def.bucketKey == null ? null : 'create:${def.bucketKey}',
        tickRate: tickRate,
        levelDecreasePerBlock: levelDecreasePerBlock,
        slopeFindDistance: slopeFindDistance,
        density: density,
        viscosity: viscosity,
        tags: tags,
      ),
    );
  }
}
