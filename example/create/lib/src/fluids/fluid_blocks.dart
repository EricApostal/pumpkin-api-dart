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
import '../common/direction.dart';
import '../common/host_bridge.dart' show BlockStates;
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/registry.dart';
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
import 'generic_item_fluid.dart';
import 'hose_pulley_entity.dart';
import 'pipe_block_entities.dart';
import 'pipe_blocks.dart';
import 'pipe_shapes.dart';
import 'pipe_state_logic.dart';
import 'pump_logic.dart';
import 'spout.dart';
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

  Future<BState> place(
    World world,
    Pos p,
    BState state,
    Direction preferred,
  ) async {
    final level = fluidWorldOf(world);
    if (smart) {
      final axis = PipeStateLogic.smartPipePreferredAxis(level, p);
      var s = state;
      if (axis == Axis.y) {
        s = s
            .setValue('face', 'wall')
            .setDir('facing', (s.dir('facing') ?? Direction.north).opposite);
      } else if (axis != null) {
        if (s['face'] == 'wall') s = s.setValue('face', 'floor');
      }
      setFluidBlock(world, p, s);
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
    if (updated != state) setFluidBlock(world, p, updated);
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
      var placed = state;
      if (smart && player != null) {
        placed = placed.setDir('facing', preferred.opposite);
      }
      final finalState = await place(world, p, placed, preferred);
      propagate(world, p, finalState);
    },
    onNeighborUpdate: (server, e) {
      final world = e.targetWorld;
      final p = posOf(e.pos);
      final state = stateOfEvent(e.stateIndex);
      final level = fluidWorldOf(world);
      var updated = state;
      if (!encased && !straight && !smart) {
        updated = PipeStateLogic.updateBlockState(
          state,
          state.dir('facing') ?? Direction.north,
          null,
          level,
          p,
        );
        if (updated != state) setFluidBlock(world, p, updated);
      }
      propagate(world, p, updated);
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
            if (!e.withItem) {
              pipe.filterFluid = null;
              pipe.sendData();
              return BlockUseResult.success;
            }
            final key = await e.item.getRegistryKey();
            final bucket = FluidRegistries.fromBucket(key);
            if (bucket != null) {
              pipe.filterFluid = bucket.fluid;
            } else {
              // `FilteringBehaviour.forFluids`: any item with a fluid handler filters that fluid.
              final handler = e.item.fluidHandler;
              final drained = handler == null
                  ? null
                  : await handler.drain(maxAmount: 1000, simulate: true);
              pipe.filterFluid = drained == null || drained.amount <= 0
                  ? null
                  : fromHostFluid(drained).fluid;
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
        await _tryTankMultiPlace(server, e, block, blockEntityType);
      },
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

/// `ComparatorUtil.fractionToRedstoneLevel`.
int fractionToRedstoneLevel(double fraction) {
  if (fraction <= 0) return 0;
  return math.min(15, (fraction * 14).floor() + 1);
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
  final item = FluidItemSpec(itemKey, count);
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
      final (emptied, _, _) = emptying.emptyItem(item, simulate: false);
      storage.fill(emptied, simulate: false);
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
      final (result, _, _) = filling.fillItem(required, item, fluid);
      if (result.isEmpty) continue;
      storage.drainFluid(fluid.withAmount(required), simulate: false);
      // A creative player keeps the fluid; a creative tank gives the item back to everyone.
      if (!player.isCreative) {
        final out = await HostStacks.write(PStack(result.key, result.count));
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
bool _placingTankRow = false;

Future<void> _tryTankMultiPlace(
  Server server,
  CustomBlockPlacedEventData e,
  CreateBlock block,
  String typeKey,
) async {
  if (_placingTankRow) return;
  final playerId = e.player;
  if (playerId == null) return;
  final player = server.getPlayerByUuid(id: playerId);
  if (player == null || player.asEntity().isSneaking()) return;

  final runtime = FluidsRuntime.instance;
  final world = e.targetWorld;
  final worldId = runtime.worlds.touch(world);
  final pos = posOf(e.pos);

  // The tank the new block was placed against, if it is part of a wide tank.
  FluidTankBlockEntity? controller;
  var onTop = false;
  for (final candidate in [pos.below, pos.above]) {
    final be = runtime.store.at(
      worldId,
      BlockPos(x: candidate.$1, y: candidate.$2, z: candidate.$3),
    );
    if (be is! FluidTankBlockEntity) continue;
    final c = be.controllerBe;
    if (c == null || c.width <= 1) continue;
    if (c.partPos.aboveBy(c.height) == pos) {
      controller = c;
      onTop = true;
      break;
    }
    if (c.partPos.below == pos) {
      controller = c;
      onTop = false;
      break;
    }
  }
  if (controller == null) return;

  final width = controller.width;
  final start = onTop
      ? controller.partPos.aboveBy(controller.height)
      : controller.partPos.below;
  final targets = <Pos>[];
  final level = fluidWorldOf(world);
  for (var x = 0; x < width; x++) {
    for (var z = 0; z < width; z++) {
      final p = start.offset(x, 0, z);
      if (PipeBlocks.isTank(level.stateAt(p))) continue;
      if (!level.canBeReplaced(p)) return;
      targets.add(p);
    }
  }
  if (targets.isEmpty) return;

  final inventory = player.getInventory();
  final items = inventory.asInventory();
  final slot = inventory.getSelectedSlot();
  final stack = items.getItem(slot: slot);
  if (!player.isCreative) {
    final count = stack == null ? 0 : await stack.getCount();
    if (count < targets.length) return;
  }

  _placingTankRow = true;
  try {
    final state = BState(block.key, block.definition.defaultState);
    final stateId = BlockRegistry.resolveState(state.key, state.props);
    if (stateId == null) return;
    for (final p in targets) {
      final bp = BlockPos(x: p.$1, y: p.$2, z: p.$3);
      await world.setBlockState(
        pos: bp,
        state: stateId,
        updateFlags: BlockUpdateFlags.normal,
      );
      runtime.store.createAt(world, bp, typeKey);
    }
    if (!player.isCreative && stack != null) {
      final count = await stack.getCount();
      if (count - targets.length <= 0) {
        await items.setItem(slot: slot, item: null);
      } else {
        await stack.setCount(count: count - targets.length);
        await items.setItem(slot: slot, item: stack);
      }
    }
    for (final p in targets) {
      final be = runtime.store.at(worldId, BlockPos(x: p.$1, y: p.$2, z: p.$3));
      if (be is FluidTankBlockEntity) be.updateConnectivityNow();
    }
  } finally {
    _placingTankRow = false;
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
      final item = FluidItemSpec(key, count);
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
              PStack(remainder.key, remainder.count),
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
  manifestBlock('honey', drops: BlockDrops.nothing),
  manifestBlock('chocolate', drops: BlockDrops.nothing),
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
      PlacementRule.lookingDirection('facing', opposite: true),
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
      PlacementRule.lookingDirection('facing', opposite: true),
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
            fluidWorldOf(c.world),
            kposOf(c),
            facing,
            look,
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
        tickRate: 5,
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
        density: density,
        viscosity: viscosity,
        tags: tags,
      ),
    );
  }
}
