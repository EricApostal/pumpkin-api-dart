// The funnel blocks: `create:andesite_funnel`, `create:brass_funnel` and their belt funnel
// variants. Placement, survival, the conversion between a funnel and a belt funnel, the shapes,
// item insertion and the wrench actions; the transfer logic is in `funnel_block_entity.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../../../core/registry.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../belt/belt_geometry.dart';
import '../../behaviours/belt_interfaces.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../../shapes.dart';
import '../transport_support.dart';
import 'funnel_block_entity.dart';

/// Phase 1: the four funnel blocks and their shared block entity type.
void registerFunnels(CreateRegistry registry) {
  final blocks = <CreateBlock>[
    manifestBlock(
      'andesite_funnel',
      blockEntityType: 'create:funnel',
      behavior: _funnelBehavior(),
      placement: const [
        PlacementRule.lookingDirection('facing', opposite: true),
        PlacementRule.sneaking('extracting', opposite: true),
        PlacementRule.inWater('waterlogged'),
      ],
    ),
    manifestBlock(
      'brass_funnel',
      blockEntityType: 'create:funnel',
      behavior: _funnelBehavior(),
      placement: const [
        PlacementRule.lookingDirection('facing', opposite: true),
        PlacementRule.sneaking('extracting', opposite: true),
        PlacementRule.inWater('waterlogged'),
      ],
    ),
    manifestBlock(
      'andesite_belt_funnel',
      blockEntityType: 'create:funnel',
      behavior: _beltFunnelBehavior(),
      placement: const [
        PlacementRule.horizontalFacing('facing'),
        PlacementRule.inWater('waterlogged'),
      ],
    ),
    manifestBlock(
      'brass_belt_funnel',
      blockEntityType: 'create:funnel',
      behavior: _beltFunnelBehavior(),
      placement: const [
        PlacementRule.horizontalFacing('facing'),
        PlacementRule.inWater('waterlogged'),
      ],
    ),
  ];
  for (final block in blocks) {
    registry.block(block);
    transportBlocks[block.key] = block;
  }
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:funnel',
      validBlocks: const [
        'andesite_funnel',
        'brass_funnel',
        'andesite_belt_funnel',
        'brass_belt_funnel',
      ],
      create: FunnelBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 3: the wrench actions of the funnels.
void registerFunnelWrench(WrenchRegistry wrench) {
  for (final key in ['create:andesite_funnel', 'create:brass_funnel']) {
    wrench.register(
      key,
      const CallbackWrenchable(onWrenchedOverride: _wrenchFunnel),
    );
  }
  for (final key in [
    'create:andesite_belt_funnel',
    'create:brass_belt_funnel',
  ]) {
    wrench.register(
      key,
      const CallbackWrenchable(onWrenchedOverride: _wrenchBeltFunnel),
    );
  }
}

Future<WrenchResult> _wrenchFunnel(WrenchContext c) async {
  final world = c.world;
  final pos = c.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
  await writeState(world, pos, state.cycleFlag('extracting'));
  return WrenchResult.success;
}

Future<WrenchResult> _wrenchBeltFunnel(WrenchContext c) async {
  final world = c.world;
  final pos = c.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
  final shape = state['shape'] ?? 'retracted';
  var next = shape;
  if (shape == 'pulling') {
    next = 'pushing';
  } else if (shape == 'pushing') {
    next = 'pulling';
  } else if (shape == 'extended') {
    next = 'retracted';
  } else if (shape == 'retracted') {
    final below = ConveyanceRuntime.i.stateAt(world.getId(), pos.below);
    next = below['slope'] == 'horizontal' || below.key != 'create:belt'
        ? 'extended'
        : 'retracted';
  }
  if (next != shape)
    await writeState(world, pos, state.setValue('shape', next));
  return WrenchResult.success;
}

BlockBehavior _funnelBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = transportState(e.block, e.stateIndex);
    final level = HostBlockGetter(world);
    if (funnelFacing(state)?.isHorizontal ?? false) {
      final converted = maybeConvertToBeltFunnel(world, pos, state, level);
      if (converted != null) {
        await writeState(world, pos, converted);
        return;
      }
    }
    if (!canSurviveFunnel(level, pos, state)) scheduleBlockTick(world, pos);
  },
  onCanPlace: (server, e) {
    final state = transportState(e.block, e.stateIndex);
    final facing = funnelFacing(state);
    if (facing == null) return true;
    final behind = ConveyanceRuntime.i.stateAt(
      e.targetWorld.getId(),
      e.pos.toPos().relative(facing.opposite),
    );
    return !isFunnelState(behind) && !isBeltFunnelState(behind);
  },
  onNeighborUpdate: (server, e) {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
    final level = HostBlockGetter(world);
    if (isFunnelState(state) && (funnelFacing(state)?.isHorizontal ?? false)) {
      final converted = maybeConvertToBeltFunnel(world, pos, state, level);
      if (converted != null) {
        ConveyanceRuntime.i.fire(
          'Converting the funnel',
          () => writeState(world, pos, converted),
        );
      }
    }
    scheduleBlockTick(world, pos);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
    if (state.key != e.block) return;
    final level = HostBlockGetter(world);
    if (!canSurviveFunnel(level, pos, state)) {
      await world.destroyBlock(
        pos: pos.toBlockPos(),
        drop: true,
        player: null,
        withParticles: true,
      );
      return;
    }
    final powered = await world.hasRedstoneNeighborSignal(pos.toBlockPos());
    if (state.flag('powered') != powered)
      await writeState(world, pos, state.setFlag('powered', powered));
  },
  onShape: (server, e) => _funnelShape(transportState(e.block, e.stateIndex)),
  onUseWithItem: (server, e) => _useFunnel(e),
  onEntityCollision: (server, e) => _funnelEntityInside(e),
);

BlockBehavior _beltFunnelBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = transportState(e.block, e.stateIndex);
    final level = HostBlockGetter(world);
    final shape = getBeltFunnelShapeForPosition(
      level,
      pos,
      funnelFacing(state) ?? Direction.north,
      state['shape'] == 'pushing',
    );
    final withShape = state.setValue('shape', shape);
    if (withShape != state) await writeState(world, pos, withShape);
    if (!isOnValidBelt(world, pos, withShape)) {
      final parent = parentFunnelState(world, pos, withShape);
      await writeState(world, pos, parent);
    }
  },
  onCanPlace: (server, e) {
    final state = transportState(e.block, e.stateIndex);
    final facing = funnelFacing(state);
    if (facing == null) return true;
    final behind = ConveyanceRuntime.i.stateAt(
      e.targetWorld.getId(),
      e.pos.toPos().relative(facing.opposite),
    );
    return !isFunnelState(behind) && !isBeltFunnelState(behind);
  },
  onNeighborUpdate: (server, e) {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
    ConveyanceRuntime.i.fire(
      'Updating the belt funnel',
      () => _updateBeltFunnel(world, pos),
    );
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
    if (state.key != e.block) return;
    final powered = await world.hasRedstoneNeighborSignal(pos.toBlockPos());
    if (state.flag('powered') != powered)
      await writeState(world, pos, state.setFlag('powered', powered));
  },
  onShape: (server, e) => _funnelShape(transportState(e.block, e.stateIndex)),
);

/// `BeltFunnelBlock.updateShape`.
Future<void> _updateBeltFunnel(World world, Pos pos) async {
  final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
  if (!isBeltFunnelState(state)) return;
  final level = HostBlockGetter(world);
  if (!isOnValidBelt(world, pos, state)) {
    await writeState(world, pos, parentFunnelState(world, pos, state));
    return;
  }
  final facing = funnelFacing(state) ?? Direction.north;
  final updated = getBeltFunnelShapeForPosition(
    level,
    pos,
    facing,
    state['shape'] == 'pushing',
  );
  final current = state['shape'];
  if (updated == current) return;
  // Don't revert wrenched states.
  if (updated == 'pushing' && current == 'pulling') return;
  if (updated == 'retracted' && current == 'extended') return;
  await writeState(world, pos, state.setValue('shape', updated));
}

/// `FunnelBlock.getEquivalentBeltFunnel` + `updateShape`: the belt funnel state when the funnel
/// stands on a valid belt, `null` otherwise.
BState? maybeConvertToBeltFunnel(
  World world,
  Pos pos,
  BState state,
  BlockGetter level,
) {
  final facing = funnelFacing(state);
  if (facing == null || !facing.isHorizontal) return null;
  final key = state.key == 'create:brass_funnel'
      ? 'create:brass_belt_funnel'
      : 'create:andesite_belt_funnel';
  final extracting = state.flag('extracting');
  final shape = getBeltFunnelShapeForPosition(level, pos, facing, extracting);
  final converted = withWater(
    world,
    BState(key, {
      'facing': facing.serializedName,
      'powered': '${state.flag('powered')}',
      'shape': shape,
      'waterlogged': '${state.flag('waterlogged')}',
    }),
    pos,
  );
  return isOnValidBelt(world, pos, converted) ? converted : null;
}

/// `BeltFunnelBlock.updateShape`: the parent funnel of a belt funnel that is no longer on a belt.
BState parentFunnelState(World world, Pos pos, BState beltState) {
  final key = beltState.key == 'create:brass_belt_funnel'
      ? 'create:brass_funnel'
      : 'create:andesite_funnel';
  return withWater(
    world,
    BState(key, {
      'facing': beltState['facing'] ?? 'north',
      'powered': '${beltState.flag('powered')}',
      'extracting': '${beltState['shape'] == 'pushing'}',
      'waterlogged': '${beltState.flag('waterlogged')}',
    }),
    pos,
  );
}

/// `BeltFunnelBlock.getShapeForPosition`.
String getBeltFunnelShapeForPosition(
  BlockGetter world,
  Pos pos,
  Direction facing,
  bool extracting,
) {
  final below = world.stateAt(pos.below);
  final perpendicular = extracting ? 'pushing' : 'pulling';
  if (below.key != 'create:belt') return perpendicular;
  final movementFacing = below.dir('facing');
  if (movementFacing == null) return perpendicular;
  return movementFacing.axis != facing.axis ? perpendicular : 'retracted';
}

/// `BeltFunnelBlock.isOnValidBelt`.
bool isOnValidBelt(World world, Pos pos, BState state) {
  final belowPos = pos.below;
  final below = ConveyanceRuntime.i.stateAt(world.getId(), belowPos);
  if (below.key == 'create:belt') return canTransportObjects(below);
  final be = ConveyanceRuntime.i.beAt(world.getId(), belowPos);
  if (be is DirectBeltInput)
    return (be as DirectBeltInput).canSupportBeltFunnels;
  return be?.getBehaviour<pt.DirectBeltInputBehaviour>()?.supportsBeltFunnels ??
      false;
}

/// `AbstractFunnelBlock.canSurvive`.
bool canSurviveFunnel(BlockGetter level, Pos pos, BState state) {
  final facing = funnelFacing(state);
  if (facing == null) return false;
  final behind = level.stateAt(pos.relative(facing.opposite));
  return !isFunnelState(behind) && !isBeltFunnelState(behind);
}

List<BlockBox> _funnelShape(BState state) {
  final facing = funnelFacing(state) ?? Direction.north;
  if (isBeltFunnelState(state)) {
    final shape = state['shape'] ?? 'retracted';
    final shaper = switch (shape) {
      'extended' => beltFunnelExtended,
      'pushing' || 'pulling' => beltFunnelPerpendicular,
      _ => beltFunnelRetracted,
    };
    return shaper.get(facing);
  }
  if (facing == Direction.down) return funnelCeiling;
  if (facing == Direction.up) return funnelFloor;
  return funnelWall.get(facing);
}

/// `AbstractFunnelBlock.canInsertIntoFunnel`.
bool _canInsertIntoFunnel(BState state) =>
    !state.flag('powered') && !state.flag('extracting');

Future<BlockUseResult> _useFunnel(CustomBlockUseEventData e) async {
  final world = e.targetWorld;
  final worldId = world.getId();
  final pos = e.pos.toPos();
  final state = transportState(e.block, e.stateIndex);
  final held = await ItemCodec.read(e.withItem ? e.item : null);
  if (held.key == 'create:wrench') return BlockUseResult.tryEmptyHand;
  if (!isFunnelState(state)) return BlockUseResult.tryEmptyHand;
  // `AllBlocks.MECHANICAL_ARM.isIn(stack)` blocks insertion, like a powered or extracting funnel.
  if (e.face.toDirection() != funnelFacing(state) ||
      !_canInsertIntoFunnel(state) ||
      held.key == 'create:mechanical_arm') {
    return BlockUseResult.tryEmptyHand;
  }
  final be = ConveyanceRuntime.i.typedAt<FunnelBlockEntity>(worldId, pos);
  if (be == null) return BlockUseResult.tryEmptyHand;
  final remainder = await tryInsertIntoFunnel(be, held, simulate: false);
  if (!remainder.matches(held)) {
    final host = await ItemCodec.write(remainder);
    await e.player.getInventory().setItemInHand(hand: e.hand, item: host);
  }
  return BlockUseResult.success;
}

/// `AbstractFunnelBlock.tryInsert`.
Future<ItemValue> tryInsertIntoFunnel(
  FunnelBlockEntity be,
  ItemValue stack, {
  required bool simulate,
}) async {
  if (!be.filtering.test(stack)) return stack;
  final inv = be.itemInventoryBehind;
  if (inv == null) return stack;
  final remainder = await insertStacked(inv, stack, simulate: simulate);
  if (!simulate && remainder.count != stack.count) {
    be.onTransfer(stack);
    be.flap(true);
  }
  return remainder;
}

Future<void> _funnelEntityInside(CustomBlockEntityCollisionEventData e) async {
  final world = e.targetWorld;
  final worldId = world.getId();
  final pos = e.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(worldId, pos);
  if (!isFunnelState(state) || !_canInsertIntoFunnel(state)) return;

  final entity = world.getEntityById(id: e.entityId);
  final item = entity?.asItem();
  if (item == null) return;
  final stack = await ItemCodec.read(item.getStack());
  if (stack.isEmpty) return;

  final direction = funnelFacing(state) ?? Direction.north;
  final center = pos.center;
  final scale = entity is ItemEntity ? -.25 : -.125;
  final open = (
    center.$1 + direction.stepX * scale,
    center.$2 + direction.stepY * scale,
    center.$3 + direction.stepZ * scale,
  );
  final diff = (
    e.entityPos.$1 - open.$1,
    e.entityPos.$2 - open.$2,
    e.entityPos.$3 - open.$3,
  );
  final projected = direction.axis.choose(diff.$1, diff.$2, diff.$3);
  if ((projected < 0) == (direction.axisDirection == AxisDirection.positive))
    return;

  final be = ConveyanceRuntime.i.typedAt<FunnelBlockEntity>(worldId, pos);
  if (be == null) return;
  final remainder = await tryInsertIntoFunnel(be, stack, simulate: false);
  if (remainder.isEmpty) {
    item.discard();
  } else if (remainder.count < stack.count) {
    final host = await ItemCodec.write(remainder);
    if (host != null) await item.setStack(stack: host);
  }
}
