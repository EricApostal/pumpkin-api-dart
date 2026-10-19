// Small host-side helpers shared by the item-transport blocks: state indexing of the blocks this
// area registers, the item-entity glue (`ItemEntity` <-> [ItemValue]), sound and tick helpers.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/blocks.dart';
import '../items/item_codec.dart';
import '../items/item_data.dart';

/// The [CreateBlock]s registered by `transport_registration.dart`, by key. Block behaviours need
/// them to turn an event's state index back into property values.
final Map<String, CreateBlock> transportBlocks = {};

/// The state of block [blockKey] with local state index [stateIndex] (as in the block events).
BState transportState(String blockKey, int stateIndex) =>
    BState(blockKey, transportBlocks[blockKey]!.stateOf(stateIndex));

/// The local state index of [state] in the layout of [blockKey], or `null` when a value is outside
/// the block's domain.
int? transportStateIndex(String blockKey, BState state) {
  final block = transportBlocks[blockKey];
  if (block == null) return null;
  try {
    return block.layout.indexOf({
      ...block.definition.defaultState,
      ...state.props,
    });
  } catch (_) {
    return null;
  }
}

// -- State predicates (AbstractChuteBlock / AbstractFunnelBlock / BeltTunnelBlock) -------------

/// `AbstractChuteBlock.isChute`.
bool isChuteState(BState s) =>
    s.key == 'create:chute' || s.key == 'create:smart_chute';

/// `AbstractChuteBlock.getChuteFacing` (smart chutes always face down).
Direction? chuteFacing(BState s) {
  if (s.key == 'create:smart_chute') return Direction.down;
  if (s.key != 'create:chute') return null;
  return s.dir('facing') ?? Direction.down;
}

/// `AbstractChuteBlock.isOpenChute`.
bool isOpenChute(BState s) {
  if (!isChuteState(s)) return false;
  if (s.key == 'create:smart_chute') return true;
  return (s.dir('facing') ?? Direction.down) == Direction.down ||
      s['shape'] == 'intersection';
}

/// `AbstractFunnelBlock.isFunnel`.
bool isFunnelState(BState s) =>
    s.key == 'create:andesite_funnel' || s.key == 'create:brass_funnel';

/// `BeltFunnelBlock`.
bool isBeltFunnelState(BState s) =>
    s.key == 'create:andesite_belt_funnel' ||
    s.key == 'create:brass_belt_funnel';

/// `AbstractFunnelBlock.getFunnelFacing`.
Direction? funnelFacing(BState s) {
  if (isFunnelState(s)) return s.dir('facing');
  if (isBeltFunnelState(s)) return s.dir('facing');
  return null;
}

/// `BeltTunnelBlock`.
bool isTunnelState(BState s) =>
    s.key == 'create:andesite_tunnel' || s.key == 'create:brass_tunnel';

/// `ItemVaultBlock.isVault`.
bool isVaultState(BState s) => s.key == 'create:item_vault';

/// `BeltTunnelBlock.isStraight`.
bool isStraightTunnel(BState s) {
  final shape = s['shape'];
  return shape == 'straight' || shape == 'window' || shape == 'closed';
}

/// `BeltTunnelBlock.isJunction`.
bool isJunctionTunnel(BState s) {
  final shape = s['shape'];
  return shape == 'cross' || shape == 't_left' || shape == 't_right';
}

// -- World helpers -----------------------------------------------------------------------------

/// Schedules the block at [pos] for a tick in [delay] ticks.
void scheduleBlockTick(World world, Pos pos, {int delay = 1}) =>
    world.scheduleBlockTick(
      pos: pos.toBlockPos(),
      delayTicks: delay,
      priority: TickPriority.normal,
    );

/// `Level.setBlockAndUpdate(pos, state)`.
Future<void> writeState(World world, Pos pos, BState state) =>
    setBlockState(world, pos, state);

/// Plays a vanilla sound event at the block centre.
void playSoundAt(
  World world,
  Pos pos,
  Sound sound, {
  double volume = 1,
  double pitch = 1,
}) => world.playSound(
  sound: sound,
  category: SoundCategory.blocks,
  pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
  volume: volume,
  pitch: pitch,
);

// -- Item entities -----------------------------------------------------------------------------

/// `ItemHelper.fromItemEntity`: the stack of [entity] when it is a dropped item, else empty.
Future<ItemValue> stackOfEntity(Entity? entity) async {
  final item = entity?.asItem();
  if (item == null) return ItemValue.empty;
  return ItemCodec.read(item.getStack());
}

/// `ItemEntity.setItem`: replaces the stack of the item entity; an empty stack discards it.
Future<void> setEntityItem(Entity? entity, ItemValue stack) async {
  final item = entity?.asItem();
  if (item == null) return;
  if (stack.isEmpty) {
    item.discard();
    return;
  }
  final hostStack = await ItemCodec.write(stack);
  if (hostStack == null) {
    item.discard();
    return;
  }
  await item.setStack(stack: hostStack);
}

/// The dropped items inside the box with corners [min] and [max].
List<ItemEntity> itemEntitiesIn(
  World world,
  (double, double, double) min,
  (double, double, double) max,
) => world.getItemEntitiesInBox(min: min, max: max);

/// `Block.popResource` at the centre of [pos].
Future<void> dropItemAt(
  World world,
  Pos pos,
  ItemValue stack, {
  double dy = .5,
}) => ItemCodec.drop(world, (pos.$1 + 0.5, pos.$2 + dy, pos.$3 + 0.5), stack);

/// `new ItemEntity(level, x, y, z, stack)` with a motion and the default pickup delay.
Future<void> spawnItemEntity(
  World world,
  (double, double, double) position,
  ItemValue stack, {
  (double, double, double) velocity = (0, 0, 0),
}) => ItemCodec.drop(world, position, stack, velocity: velocity);
