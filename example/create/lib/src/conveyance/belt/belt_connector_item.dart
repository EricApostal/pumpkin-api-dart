// `BeltConnectorItem` (host): the item that creates belts between two shafts. The first use
// stores the shaft in the `create:belt_first_shaft` component; the second connects them with
// `BeltConnectorItem.createBelts`. Ported from
// `content/kinetics/belt/item/BeltConnectorItem.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/registry.dart' show RegistryKind;

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, setBlockState;
import '../../api/kinetics.dart' show KState;
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/pos.dart' show packPos, unpackPos;
import '../runtime.dart';
import 'belt_geometry.dart';

/// `create:belt_connector`.
const String beltConnectorKey = 'create:belt_connector';

/// The data component the first shaft is stored in (`AllDataComponents.BELT_FIRST_SHAFT`).
const String _firstShaftComponent = 'create:belt_first_shaft';

/// `BeltConnectorItem.useOn` through the `itemUseFirst` hook. Returns whether the use was handled.
Future<bool> useBeltConnector(
  ConveyanceRuntime rt,
  ItemUseFirstEventData e,
) async {
  if (e.useResult != ItemUseFirstResult.pass) return false;

  // The event carries a copy of the held stack (`ItemUseFirstEvent.stack`); the host does not
  // read it back. Work on the hand stack and write it back after every change, or the pending
  // first shaft is lost with the copy and the second click can never connect (`useOn`).
  final player = e.player;
  final hand = e.hand;
  final held = player.getItemInHand(hand: hand);
  if (held == null) return false;
  final String key;
  try {
    key = await held.getRegistryKey();
  } on Object {
    return false;
  }
  if (key != beltConnectorKey) return false;

  final world = player.getWorld();
  final worldId = rt.ctx.worlds.touch(world);
  final pos = e.blockPos.toPos();

  if (_isSneaking(player)) {
    _clearFirst(held);
    await _setHeld(player, hand, held);
    return true;
  }

  final validAxis = _validateAxis(world, pos);
  var firstPulley = _readFirst(held);
  var staleCleared = false;
  if (firstPulley != null &&
      (!_validateAxis(world, firstPulley) ||
          !firstPulley.closerThan(pos, rt.maxBeltLength * 2))) {
    _clearFirst(held);
    staleCleared = true;
    firstPulley = null;
  }

  if (!validAxis) {
    // Java removes a stale first shaft before it fails the click.
    if (staleCleared) await _setHeld(player, hand, held);
    return false;
  }

  if (firstPulley != null) {
    if (!canConnectBelt(
      HostBlockGetter(world),
      firstPulley,
      pos,
      rt.maxBeltLength,
      (at) => _speedAt(rt, worldId, at),
    )) {
      return false;
    }
    if (firstPulley != pos) {
      await createBelts(rt, world, worldId, firstPulley, pos);
      await rt.award(player, 'create:belt');
      if (!player.isCreative) await _consumeOne(player, hand);
    }
    // Java removes the component from the (possibly shrunk) stack in the hand.
    final remaining = player.getItemInHand(hand: hand);
    if (remaining != null) {
      _clearFirst(remaining);
      await _setHeld(player, hand, remaining);
    }
    return true;
  }

  _writeFirst(held, pos);
  await _setHeld(player, hand, held);
  return true;
}

/// Writes [stack] back to [hand]. The host hands out copies, so a component written to a
/// stack is lost unless the stack is put back (`ItemStack` in the hand is not a live handle).
Future<void> _setHeld(Player player, Hand hand, ItemStack stack) =>
    player.setItemInHand(hand: hand, stack: stack);

/// `BeltConnectorItem.createBelts`.
Future<void> createBelts(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos start,
  Pos end,
) async {
  final mid = (
    (start.x + end.x) / 2,
    (start.y + end.y) / 2,
    (start.z + end.z) / 2,
  );
  rt.playSound(
    world,
    (mid.$1.floor(), mid.$2.floor(), mid.$3.floor()),
    'minecraft:block.wool.place',
    volume: .5,
    pitch: 1,
  );

  final getter = HostBlockGetter(world);
  final planned = planBelts(start, end, getter);
  final created = <Pos>[];

  for (final (at, part, slope, facing) in planned) {
    if (!getter.canBeReplaced(at)) {
      await world.breakBlock(at.toBlockPos(), drop: false);
    }
    final state = BState('create:belt', {
      'casing': 'false',
      'facing': facing.serializedName,
      'part': part.name,
      'slope': slope.name,
      'waterlogged': '${_waterAt(world, at)}',
    });
    await _switch(rt, world, worldId, at, state);
    created.add(at);
  }
}

bool _validateAxis(World world, Pos pos) {
  if (!world.isLoaded(pos: pos.toBlockPos())) return false;
  return HostBlockGetter(world).stateAt(pos).key == 'create:shaft';
}

double? _speedAt(ConveyanceRuntime rt, String worldId, Pos pos) {
  final be = rt.kinetics?.kineticAt(worldId, pos.toBlockPos());
  return be?.theoreticalSpeed;
}

bool _waterAt(World world, Pos pos) {
  final fluid = world.getFluidState(pos: pos.toBlockPos());
  return fluid != null && fluid.fluid == 'minecraft:water' && fluid.isSource;
}

Future<void> _switch(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos pos,
  BState state,
) async {
  final kinetics = rt.kinetics;
  if (kinetics != null) {
    await kinetics.switchToBlockState(
      worldId,
      pos.toBlockPos(),
      KState(state.key, state.props),
    );
    return;
  }
  final id = rt.ctx.ids.of(RegistryKind.blocks, state.key);
  if (id == null) return;
  await setBlockState(world, pos, state);
}

/// The stored first shaft (`BlockPos.STREAM_CODEC`: one big-endian long, the
/// bytes of `BlockPos.asLong`).
Pos? _readFirst(ItemStack stack) {
  final bytes = stack.customComponent(_firstShaftComponent);
  if (bytes == null || bytes.length < 8) return null;
  var packed = 0;
  for (var i = 0; i < 8; i++) {
    packed = (packed << 8) | (bytes[i] & 0xff);
  }
  return unpackPos(packed);
}

void _writeFirst(ItemStack stack, Pos pos) {
  final packed = packPos(pos.x, pos.y, pos.z);
  final bytes = List<int>.generate(
    8,
    (i) => (packed >> (8 * (7 - i))) & 0xff,
  );
  stack.setCustomComponent(_firstShaftComponent, bytes);
}

void _clearFirst(ItemStack stack) {
  try {
    stack.removeCustomComponent(_firstShaftComponent);
  } on Object {
    // the stack has no component: nothing to clear
  }
}

bool _isSneaking(Player player) {
  final entity = player.asEntity();
  try {
    return entity.isSneaking();
  } finally {
    entity.dispose();
  }
}

Future<void> _consumeOne(Player player, Hand hand) async {
  final held = player.getItemInHand(hand: hand);
  if (held == null) return;
  final count = await held.getCount();
  if (count <= 1) {
    await player.setItemInHand(hand: hand, stack: null);
  } else {
    await held.setCount(count: count - 1);
    // `getItemInHand` is a copy: the decremented count only exists once it is written back.
    await player.setItemInHand(hand: hand, stack: held);
  }
}
