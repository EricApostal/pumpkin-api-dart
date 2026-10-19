// The chute blocks: `create:chute` (shapes, diagonal placement, the `SHAPE` state) and
// `create:smart_chute` (the redstone gate). The item movement lives in `chute_block_entity.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../core/registry.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../../shapes.dart';
import '../transport_inventory.dart';
import '../transport_support.dart';
import 'chute_block_entity.dart';

/// Phase 1: the two chute blocks and their block entities.
void registerChutes(CreateRegistry registry) {
  final chute = manifestBlock(
    'chute',
    blockEntityType: 'create:chute',
    behavior: _chuteBehavior(),
    placement: const [
      PlacementRule.clickedFaceDown('facing'),
      PlacementRule.inWater('waterlogged'),
    ],
  );
  final smartChute = manifestBlock(
    'smart_chute',
    blockEntityType: 'create:smart_chute',
    behavior: _smartChuteBehavior(),
  );
  for (final block in [chute, smartChute]) {
    registry.block(block);
    transportBlocks[block.key] = block;
  }
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:chute',
      validBlocks: const ['create:chute'],
      create: ChuteBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:smart_chute',
      validBlocks: const ['create:smart_chute'],
      create: SmartChuteBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 3: the wrench actions of the chutes.
void registerChuteWrench(WrenchRegistry wrench) {
  wrench.register(
    'create:chute',
    const CallbackWrenchable(onWrenchedOverride: _wrenchChute),
  );
  wrench.registerDefault(const ['create:smart_chute']);
}

Future<WrenchResult> _wrenchChute(WrenchContext c) async {
  final world = c.world;
  final pos = c.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
  final shape = state['shape'] ?? 'normal';
  if (shape == 'intersection') return WrenchResult.pass;
  if (shape == 'encased') {
    await writeState(world, pos, state.setValue('shape', 'normal'));
    return WrenchResult.success;
  }
  if ((state.dir('facing') ?? Direction.down) == Direction.down) {
    await writeState(
      world,
      pos,
      state.setValue('shape', shape != 'normal' ? 'normal' : 'window'),
    );
  }
  return WrenchResult.success;
}

BlockBehavior _chuteBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = transportState(e.block, e.stateIndex);
    final level = HostBlockGetter(world);
    final fixed = updateChuteState(
      placed,
      level.stateAt(pos.above),
      level,
      pos,
    );
    if (fixed != placed) await writeState(world, pos, fixed);
    ConveyanceRuntime.i
        .typedAt<ChuteBlockEntity>(world.getId(), pos)
        ?.onAdded();
  },
  onCanPlace: (server, e) {
    final above = ConveyanceRuntime.i.stateAt(
      e.targetWorld.getId(),
      e.pos.toPos().above,
    );
    return !isChuteState(above) || chuteFacing(above) == Direction.down;
  },
  onUpdateShape: (server, e) async {
    final pos = e.pos.toPos();
    final state = transportState(e.block, e.stateIndex);
    if (state.flag('waterlogged')) updateWater(e.targetWorld, pos, state);
    if (e.direction.toDirection() != Direction.up) return null;
    final level = HostBlockGetter(e.targetWorld);
    final next = updateChuteState(state, level.stateAt(pos.above), level, pos);
    return transportStateIndex(e.block, next);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = ConveyanceRuntime.i.stateAt(world.getId(), pos);
    if (state.key != e.block) return;
    final level = HostBlockGetter(world);
    final next = updateChuteState(state, level.stateAt(pos.above), level, pos);
    if (next != state) await writeState(world, pos, next);
  },
  onNeighborUpdate: (server, e) {
    final pos = e.pos.toPos();
    scheduleBlockTick(e.targetWorld, pos);
    final delta = e.sourcePos.toPos() - pos;
    final d = Direction.fromDelta(delta.$1, delta.$2, delta.$3);
    if (d == Direction.down) {
      ConveyanceRuntime.i
          .typedAt<ChuteBlockEntity>(e.targetWorld.getId(), pos)
          ?.blockBelowChanged();
    }
  },
  onShape: (server, e) {
    final state = transportState(e.block, e.stateIndex);
    return e.kind == BlockShapeKind.collision
        ? ChuteShapes.getCollisionShape(state)
        : ChuteShapes.getShape(state);
  },
  onUseWithItem: (server, e) => _useChute(e),
  onUseWithoutItem: (server, e) => _useChute(e),
);

BlockBehavior _smartChuteBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = transportState(e.block, e.stateIndex);
    final powered = await world.hasRedstoneNeighborSignal(pos.toBlockPos());
    if (state.flag('powered') != powered)
      await writeState(world, pos, state.setFlag('powered', powered));
  },
  onNeighborUpdate: (server, e) {
    scheduleBlockTick(e.targetWorld, e.pos.toPos());
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
  onShape: (server, e) {
    final state = transportState(e.block, e.stateIndex);
    return e.kind == BlockShapeKind.collision
        ? ChuteShapes.getCollisionShape(state)
        : ChuteShapes.getShape(state);
  },
  onUseWithItem: (server, e) => _useChute(e),
  onUseWithoutItem: (server, e) => _useChute(e),
);

/// `AbstractChuteBlock.useItemOn`: encase with industrial iron, place a chute diagonally, or take
/// the held item out of the chute.
Future<BlockUseResult> _useChute(CustomBlockUseEventData e) async {
  final world = e.targetWorld;
  final worldId = world.getId();
  final pos = e.pos.toPos();
  final state = transportState(e.block, e.stateIndex);
  final held = await ItemCodec.read(e.withItem ? e.item : null);
  final be = ConveyanceRuntime.i.typedAt<ChuteBlockEntity>(worldId, pos);

  if (held.key == 'create:industrial_iron_block' && e.block == 'create:chute') {
    final shape = state['shape'];
    if (shape != 'intersection' && shape != 'encased') {
      await writeState(world, pos, state.setValue('shape', 'encased'));
      playSoundAt(
        world,
        pos,
        Sound.blockNetheriteBlockHit,
        volume: .5,
        pitch: 1.05,
      );
      return BlockUseResult.success;
    }
  }

  // `ChuteItem.place`: right-clicking the side of a chute with a chute item stacks it on top.
  if (held.key == 'create:chute' &&
      e.block == 'create:chute' &&
      !e.sneaking &&
      e.face.toDirection().isHorizontal) {
    final face = e.face.toDirection();
    final level = HostBlockGetter(world);
    // In a use event `e.pos` is the clicked block, so the placement position is its neighbour
    // and the chute item's `correctPos` is one above that.
    final correctPos = pos.relative(face).above;
    if (level.canBeReplaced(correctPos)) {
      final placed = withWater(
        world,
        BState('create:chute', {
          'facing': face.serializedName,
          'shape': 'normal',
        }),
        correctPos,
      );
      final fixed = updateChuteState(
        placed,
        level.stateAt(correctPos.above),
        level,
        correctPos,
      );
      await writeState(world, correctPos, fixed);
      await _shrinkHeld(e.player, e.hand);
      return BlockUseResult.success;
    }
    final atCorrectPos = level.stateAt(correctPos);
    if (atCorrectPos.key == 'create:chute' &&
        (atCorrectPos.dir('facing') ?? Direction.down) == Direction.down) {
      final fixed = updateChuteState(
        withWater(world, atCorrectPos.setDir('facing', face), correctPos),
        level.stateAt(correctPos.above),
        level,
        correctPos,
      );
      await writeState(world, correctPos, fixed);
      await _shrinkHeld(e.player, e.hand);
      return BlockUseResult.success;
    }
    return BlockUseResult.fail;
  }

  if (be == null || be.item.isEmpty) return BlockUseResult.tryEmptyHand;
  final taken = be.item;
  be.setItem(ItemValue.empty);
  await giveToPlayer(e.player, taken);
  return BlockUseResult.success;
}

Future<void> _shrinkHeld(Player player, Hand hand) async {
  final held = player.getItemInHand(hand: hand);
  if (held == null) return;
  final count = await held.getCount();
  final inv = player.getInventory();
  if (count <= 1) {
    await inv.setItemInHand(hand: hand, item: null);
  } else {
    await held.setCount(count: count - 1);
    await inv.setItemInHand(hand: hand, item: held);
  }
}

/// `ChuteBlock.updateChuteState`: recompute the shape of a chute from its diagonal neighbours.
BState updateChuteState(
  BState state,
  BState above,
  BlockGetter world,
  Pos pos,
) {
  if (state.key != 'create:chute') return state;

  final connections = <Direction, bool>{};
  var amount = 0;
  final facing = state.dir('facing') ?? Direction.down;
  final vertical = facing == Direction.down;

  if (!vertical) {
    final target = world.stateAt(pos.below.relative(facing.opposite));
    if (!isChuteState(target)) {
      return state.setDir('facing', Direction.down).setValue('shape', 'normal');
    }
  }

  for (final direction in Direction.planeHorizontal) {
    final diagonal = world.stateAt(pos.above.relative(direction));
    final value =
        diagonal.key == 'create:chute' && diagonal.dir('facing') == direction;
    connections[direction] = value;
    if (value) amount++;
  }

  final noConnections = amount == 0;
  final current = state['shape'] ?? 'normal';
  if (vertical) {
    return state.setValue(
      'shape',
      noConnections
          ? (current == 'intersection' ? 'normal' : current)
          : 'intersection',
    );
  }
  if (noConnections) return state.setValue('shape', 'intersection');
  if (connections[Direction.north] == true &&
      connections[Direction.south] == true) {
    return state.setValue('shape', 'intersection');
  }
  if (connections[Direction.east] == true &&
      connections[Direction.west] == true) {
    return state.setValue('shape', 'intersection');
  }
  final aboveFunnel =
      above.key == 'create:andesite_funnel' ||
      above.key == 'create:brass_funnel';
  if (amount == 1 &&
      connections[facing] == true &&
      chuteFacing(above) != Direction.down &&
      !(aboveFunnel && funnelFacing(above) == Direction.down)) {
    return state.setValue('shape', current == 'encased' ? 'encased' : 'normal');
  }
  return state.setValue('shape', 'intersection');
}
