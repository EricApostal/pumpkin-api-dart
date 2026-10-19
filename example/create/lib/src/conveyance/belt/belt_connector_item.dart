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
  final String key;
  try {
    key = await e.stack.getRegistryKey();
  } on Object {
    return false;
  }
  if (key != beltConnectorKey) return false;

  final player = e.player;
  final world = player.getWorld();
  final worldId = rt.ctx.worlds.touch(world);
  final pos = e.blockPos.toPos();

  if (_isSneaking(player)) {
    _clearFirst(e.stack);
    return true;
  }

  final validAxis = _validateAxis(world, pos);
  var firstPulley = _readFirst(e.stack);
  if (firstPulley != null &&
      (!_validateAxis(world, firstPulley) ||
          !firstPulley.closerThan(pos, rt.maxBeltLength * 2))) {
    _clearFirst(e.stack);
    firstPulley = null;
  }

  if (!validAxis) return false;

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
      if (!player.isCreative) await _consumeOne(player, e);
    }
    _clearFirst(e.stack);
    return true;
  }

  _writeFirst(e.stack, pos);
  return true;
}

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

Pos? _readFirst(ItemStack stack) {
  final bytes = stack.customComponent(_firstShaftComponent);
  if (bytes == null || bytes.length < 8) return null;
  var packed = 0;
  for (var i = 0; i < 8; i++) {
    packed |= (bytes[i] & 0xff) << (8 * i);
  }
  return unpackPos(packed);
}

void _writeFirst(ItemStack stack, Pos pos) {
  final packed = packPos(pos.x, pos.y, pos.z);
  final bytes = List<int>.generate(8, (i) => (packed >> (8 * i)) & 0xff);
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

Future<void> _consumeOne(Player player, ItemUseFirstEventData e) async {
  final count = await e.stack.getCount();
  final held = player.getItemInHand(hand: e.hand);
  if (held == null) return;
  if (count <= 1) {
    await player.setItemInHand(hand: e.hand, stack: null);
  } else {
    await held.setCount(count: count - 1);
  }
}
