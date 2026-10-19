// The tunnel blocks: `create:andesite_tunnel` and `create:brass_tunnel`. The block state (shape
// and axis) is recomputed from the belt below and the valid outputs; the transfer and the brass
// distribution live in `tunnel_block_entity.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../core/registry.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../runtime.dart';
import '../../shapes.dart';
import '../transport_inventory.dart';
import '../transport_support.dart';
import 'tunnel_block_entity.dart';

/// Phase 1: the two tunnel blocks and their block entities.
void registerTunnels(CreateRegistry registry) {
  for (final key in ['andesite_tunnel', 'brass_tunnel']) {
    final block = manifestBlock(
      key,
      blockEntityType: 'create:$key',
      behavior: _tunnelBehavior(),
    );
    registry.block(block);
    transportBlocks[block.key] = block;
  }
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:andesite_tunnel',
      validBlocks: const ['create:andesite_tunnel'],
      create: BeltTunnelBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:brass_tunnel',
      validBlocks: const ['create:brass_tunnel'],
      create: BrassTunnelBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 3: the wrench actions of the tunnels.
void registerTunnelWrench(WrenchRegistry wrench) {
  wrench.registerAll(const [
    'create:andesite_tunnel',
    'create:brass_tunnel',
  ], const CallbackWrenchable(onWrenchedOverride: _wrenchTunnel));
}

Future<WrenchResult> _wrenchTunnel(WrenchContext c) async {
  final world = c.world;
  final pos = c.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
  if (!hasWindow(state)) return WrenchResult.pass;
  final shape = state['shape'] == 'closed' ? 'window' : 'closed';
  await writeState(world, pos, state.setValue('shape', shape));
  return WrenchResult.success;
}

BlockBehavior _tunnelBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = getTunnelState(level, world.getId(), pos, e.block);
    if (state != transportState(e.block, e.stateIndex))
      await writeState(world, pos, state);
    final be = ConveyanceRuntime.i.beAt(world.getId(), pos);
    if (be is BeltTunnelBlockEntity)
      be.updateTunnelConnections();
  },
  onCanPlace: (server, e) {
    final below = ConveyanceRuntime.i.stateAt(
      e.targetWorld.getId(),
      e.pos.toPos().below,
    );
    if (below.key != 'create:belt') return false;
    if (below['slope'] != 'horizontal') return false;
    return below.flag('casing');
  },
  onNeighborUpdate: (server, e) async {
    final world = e.targetWorld;
    final worldId = world.getId();
    final pos = e.pos.toPos();
    final delta = e.sourcePos.toPos() - pos;
    final direction = Direction.fromDelta(delta.$1, delta.$2, delta.$3);
    if (direction == null || direction.isVertical) return;
    final be = ConveyanceRuntime.i.beAt(worldId, pos);
    if (be is BeltTunnelBlockEntity)
      be.updateTunnelConnections();

    final level = HostBlockGetter(world);
    final state = ConveyanceRuntime.i.stateAt(worldId, pos);
    if (!canSurviveTunnel(level, pos)) {
      await world.destroyBlock(
        pos: pos.toBlockPos(),
        drop: true,
        player: null,
        withParticles: true,
      );
      return;
    }
    final tunnelState = getTunnelState(level, worldId, pos, e.block);
    if ((tunnelState.axisOf('axis') ?? Axis.x) ==
            (state.axisOf('axis') ?? Axis.x) &&
        hasWindow(tunnelState) == hasWindow(state)) {
      return;
    }
    await writeState(world, pos, tunnelState);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final worldId = world.getId();
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(worldId, pos);
    if (state.key != e.block) return;
    final level = HostBlockGetter(world);
    if (!canSurviveTunnel(level, pos)) {
      await world.destroyBlock(
        pos: pos.toBlockPos(),
        drop: true,
        player: null,
        withParticles: true,
      );
      return;
    }
    final tunnelState = getTunnelState(level, worldId, pos, e.block);
    if (tunnelState != state) await writeState(world, pos, tunnelState);
  },
  onShape: (server, e) =>
      BeltTunnelShapes.getShape(transportState(e.block, e.stateIndex)),
  onUseWithoutItem: (server, e) async {
    if (e.block != 'create:brass_tunnel') return BlockUseResult.pass;
    final be = ConveyanceRuntime.i.typedAt<BrassTunnelBlockEntity>(
      e.targetWorld.getId(),
      e.pos.toPos(),
    );
    if (be == null) return BlockUseResult.pass;
    final stacks = be.grabAllStacksOfGroup(false);
    if (stacks.isEmpty) return BlockUseResult.pass;
    for (final stack in stacks) {
      await giveToPlayer(e.player, stack);
    }
    playSoundAt(
      e.targetWorld,
      e.pos.toPos(),
      Sound.entityItemPickup,
      volume: .2,
      pitch: 1,
    );
    return BlockUseResult.success;
  },
);

/// `BeltTunnelBlock.getTunnelState`.
BState getTunnelState(
  BlockGetter level,
  String worldId,
  Pos pos,
  String blockKey,
) {
  final block = transportBlocks[blockKey]!;
  var state = BState(blockKey, {...block.definition.defaultState});
  final belt = level.stateAt(pos.below);
  if (belt.key == 'create:belt') {
    state = state.setValue(
      'axis',
      (belt.axisOf('facing') ?? Axis.x).serializedName,
    );
  }
  final axis = state.axisOf('axis') ?? Axis.x;

  final left = Direction.fromAxisAndDirection(
    axis,
    AxisDirection.positive,
  ).clockWise;
  final onLeft = hasValidOutput(level, worldId, pos.below, left);
  final onRight = hasValidOutput(level, worldId, pos.below, left.opposite);

  if (onLeft && onRight) {
    state = state.setValue('shape', 'cross');
  } else if (onLeft) {
    state = state.setValue('shape', 't_left');
  } else if (onRight) {
    state = state.setValue('shape', 't_right');
  }

  if (state['shape'] == 'straight' && canHaveWindow(level, pos, axis)) {
    state = state.setValue('shape', 'window');
  }
  return state;
}

/// `BeltTunnelBlock.hasValidOutput`.
bool hasValidOutput(
  BlockGetter level,
  String worldId,
  Pos pos,
  Direction side,
) {
  final state = level.stateAt(pos.relative(side));
  if (state.key == 'create:belt')
    return (state.axisOf('facing') ?? Axis.x) == side.axis;
  final be = ConveyanceRuntime.i.beAt(worldId, pos.relative(side));
  if (be is DirectBeltInput)
    return (be as DirectBeltInput).canInsertFromSide(side);
  return be?.getBehaviour<pt.DirectBeltInputBehaviour>()?.canInsertFromSide(
        side.serializedName,
      ) ??
      false;
}

/// `BeltTunnelBlock.canHaveWindow`.
bool canHaveWindow(BlockGetter level, Pos pos, Axis axis) {
  final forward = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
  final state1 = level.stateAt(pos.relative(forward));
  final state2 = level.stateAt(pos.relative(forward.opposite));

  final funnel1 =
      isBeltFunnelState(state1) &&
      state1['shape'] == 'extended' &&
      state1.dir('facing') == forward.opposite;
  final funnel2 =
      isBeltFunnelState(state2) &&
      state2['shape'] == 'extended' &&
      state2.dir('facing') == forward;

  final valid1 = isTunnelState(state1) || funnel1;
  final valid2 = isTunnelState(state2) || funnel2;
  return valid1 && valid2 && !(funnel1 && funnel2);
}

/// `BeltTunnelBlock.hasWindow`.
bool hasWindow(BState state) {
  final shape = state['shape'];
  return shape == 'window' || shape == 'closed';
}

/// `BeltTunnelBlock.canSurvive`.
bool canSurviveTunnel(BlockGetter level, Pos pos) {
  final below = level.stateAt(pos.below);
  if (below.key != 'create:belt') return false;
  if (below['slope'] != 'horizontal') return false;
  return below.flag('casing');
}
