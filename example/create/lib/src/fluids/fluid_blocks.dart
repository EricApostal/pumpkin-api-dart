// The blocks of the fluids module: the pipes, the mechanical pump, the fluid
// valve, the tanks, the spout, the item drain and the hose pulley. The specs
// come from the manifest; this file adds the placement, neighbour, use and
// comparator behaviour and the block entity types.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show manifestBlock;
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/registry.dart';
import '../kinetics/behavior_builder.dart';
import '../kinetics/block_defs.dart';
import '../kinetics/geometry.dart' show Dir, KAxis, KState;
import '../processing/common/stack.dart' show PStack;
import '../processing/host/stack_host.dart' show HostStacks;
import '../manifest/manifest.dart';
import '../manifest/registries.g.dart' show kFluids;
import 'drain.dart';
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
import 'pipe_state_logic.dart';
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
  block = manifestBlock(
    key,
    blockEntityType: blockEntityType,
    placement: placement,
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
    onStateReplaced: (server, e) =>
        propagate(e.targetWorld, posOf(e.pos), stateOfEvent(e.oldStateIndex)),
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
              pipe.filterFluid = null;
            }
            pipe.sendData();
            propagate(e.targetWorld, posOf(e.pos), stateOfEvent(e.stateIndex));
            return BlockUseResult.success;
          }
        : null,
  );
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
        // `updateShape`: a change below refreshes the boiler temperature.
        final world = e.targetWorld;
        final p = posOf(e.pos);
        final below = p.below;
        final stateBelow = fluidWorldOf(world).stateAt(below);
        if (!PipeBlocks.isTank(stateBelow)) {
          final be = FluidsRuntime.instance.store.at(
            FluidsRuntime.instance.worlds.touch(world),
            e.pos,
          );
          if (be is FluidTankBlockEntity) be.updateBoilerTemperature();
        }
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

/// `FluidTankBlock.useItemOn`: moves fluid between the held item and the tank.
Future<BlockUseResult> _tankUse(
  bool creative,
  CustomBlockUseEventData e,
) async {
  if (!e.withItem) return BlockUseResult.tryEmptyHand;
  final worldId = FluidsRuntime.instance.worlds.touch(e.targetWorld);
  final be = FluidsRuntime.instance.store.at(worldId, e.pos);
  if (be is! FluidTankBlockEntity) return BlockUseResult.pass;
  final controller = be.controllerBe;
  final storage = controller?.fluidHandler ?? be.fluidHandler;
  if (storage == null) return BlockUseResult.tryEmptyHand;

  final inventory = e.player.getInventory();
  final items = inventory.asInventory();
  final slot = inventory.getSelectedSlot();
  final stack = items.getItem(slot: slot);
  if (stack == null) return BlockUseResult.tryEmptyHand;
  final handler = stack.fluidHandler;
  if (handler == null) return BlockUseResult.tryEmptyHand;

  // Item -> tank.
  final drained = await handler.drain(maxAmount: 1000, simulate: true);
  if (drained != null && drained.amount > 0) {
    final accepted = storage.fill(fromHostFluid(drained), simulate: true);
    if (accepted > 0) {
      final actual = await handler.drain(maxAmount: accepted, simulate: false);
      if (actual != null) {
        if (creative && be is CreativeFluidTankBlockEntity) {
          be.setContainedFluid(fromHostFluid(actual));
        } else {
          storage.fill(fromHostFluid(actual), simulate: false);
        }
        await items.setItem(slot: slot, item: stack);
        controller?.sendDataImmediately();
        return BlockUseResult.success;
      }
    }
  }

  // Tank -> item.
  final contained = storage.fluidInTank(0);
  if (contained.isNotEmpty) {
    final fits = await handler.fill(
      stack: toHostFluid(contained),
      simulate: true,
    );
    if (fits > 0) {
      if (creative && be is CreativeFluidTankBlockEntity)
        be.setContainedFluid(FStack.empty);
      final taken = storage.drain(fits, simulate: false);
      await handler.fill(stack: toHostFluid(taken), simulate: false);
      await items.setItem(slot: slot, item: stack);
      controller?.sendDataImmediately();
      return BlockUseResult.success;
    }
  }

  return BlockUseResult.tryEmptyHand;
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
    return BlockUseResult.success;
  }
  return BlockUseResult.tryEmptyHand;
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
      PlacementRule.lookingDirection('facing', opposite: true),
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
  block = manifestBlock(
    'mechanical_pump',
    blockEntityType: 'create:mechanical_pump',
    placement: [
      PlacementRule.lookingDirection('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: buildKineticBehavior(
      () => block,
      neighbor: (c, e) => _kineticNeighbour(c, e),
      scheduledTick: (c) => _propagateKinetic(c),
      replaced: (c, e) => _propagateKinetic(c),
      afterPlaced: (c, e) {
        final playerId = e.player;
        if (playerId == null) return;
        final player = c.server.getPlayerByUuid(id: playerId);
        if (player == null) return;
        final preferred = PipeStateLogic.pumpPreferredFacing(
          fluidWorldOf(c.world),
          kposOf(c),
          nearestLooking(player),
          player.asEntity().isSneaking(),
        );
        if (preferred != null) {
          unawaited(
            c.setState(c.state.set('facing', preferred.serializedName)),
          );
        }
        _propagateKinetic(c);
      },
    ),
  );
  return block;
}

/// `FluidValveBlock`: the kinetic valve.
CreateBlock valveBlock() {
  late final CreateBlock block;
  block = manifestBlock(
    'fluid_valve',
    blockEntityType: 'create:fluid_valve',
    placement: [
      PlacementRule.lookingDirection('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: buildKineticBehavior(
      () => block,
      neighbor: (c, e) => _kineticNeighbour(c, e),
      scheduledTick: (c) => _propagateKinetic(c),
      replaced: (c, e) => _propagateKinetic(c),
      afterPlaced: (c, e) => _propagateKinetic(c),
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
        final preferred = PipeStateLogic.hosePulleyPreferredSide(
          fluidWorldOf(c.world),
          kposOf(c),
        );
        if (preferred == null) return;
        final facing = preferred.opposite;
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

void _propagateKinetic(HookCtx c) => FluidPropagator.propagateChangedPipe(
  fluidWorldOf(c.world),
  kposOf(c),
  c.state.bState,
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
  'create:mechanical_pump': FacingAxisBlockDef(),
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

/// Registers the fluids of the manifest: the flowing variant first, then the
/// still fluid that names it.
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
