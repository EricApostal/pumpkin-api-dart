// `SuperGlueHandler`: glue from the off hand is applied when a block is placed, and blocks placed
// next to a glue show the glue effect on the clients that track them.
//
// Java: `content/contraptions/glue/SuperGlueHandler` (the `EntityPlaceEvent` subscriber).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../blocks/actuator_contract.dart';
import 'super_glue_entity.dart';
import 'super_glue_selection_helper.dart';

/// `glueListensForBlockPlacement`.
Future<void> onBlockPlaced(Server server, BlockPlaceEventData e) async {
  final world = e.player.getWorld();
  final worldId = world.getId();
  final glueHost = ActuatorHosts.glue;
  if (glueHost == null) return;

  final pos = (e.blockPos.x, e.blockPos.y, e.blockPos.z);
  final level = ActuatorHosts.levelOf(worldId);
  if (level == null) return;

  // The placed block may be held by glue on any of its faces.
  final nearby = glueHost.gluesIn(worldId, glueSpan(pos, pos).inflate(1));
  final cached = <int>{};
  for (final direction in Direction.values) {
    if (isGlued(nearby, pos, direction, cached)) {
      _sendGlueEffect(world, pos, direction, true);
    }
  }

  await _glueInOffHand(world, pos, e.player);
}

/// `glueInOffHandAppliesOnBlockPlace`: the off hand glue sticks the placed block to the block it
/// was placed against and uses one charge.
Future<void> _glueInOffHand(World world, Pos pos, Player player) async {
  final glueHost = ActuatorHosts.glue;
  final level = ActuatorHosts.levelOf(world.getId());
  if (glueHost == null || level == null) return;

  final inventory = player.getInventory();
  final offHand = inventory.getItemInHand(hand: Hand.left);
  if (offHand == null) return;
  final String offHandKey;
  final ItemStack mainHand;
  try {
    offHandKey = await offHand.getRegistryKey();
    final main = inventory.getItemInHand(hand: Hand.right);
    mainHand = main ?? ItemStack.create(registryKey: 'minecraft:air', count: 0);
  } catch (_) {
    return;
  }
  if (offHandKey != 'create:super_glue') return;
  final mainKey = await mainHand.getRegistryKey();
  if (mainKey == 'create:wrench') return;

  // The placed block is glued to the block the player looks at. The host place event carries the
  // neighbour's block key but not its position, so the look direction is the reliable face here.
  final entity = player.asEntity();
  final yaw = entity.getYaw() * math.pi / 180;
  final pitch = entity.getPitch() * math.pi / 180;
  final look = (
    -math.sin(yaw) * math.cos(pitch),
    -math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  );
  final face = Direction.nearest(look.$1, look.$2, look.$3);
  final gluePos = pos.relative(face.opposite);

  if (!isValidGlueFace(level, gluePos, face)) return;
  if (isGlued(
    glueHost.gluesIn(
      world.getId(),
      glueSpan(gluePos, gluePos.relative(face)).inflate(16),
    ),
    gluePos,
    face,
  )) {
    return;
  }

  if (!await collectGlueFromInventory(player, 1, simulate: true)) return;
  await collectGlueFromInventory(player, 1, simulate: false);
  glueHost.spawn(world.getId(), glueSpan(gluePos, gluePos.relative(face)));
  _sendGlueEffect(world, gluePos, face, true);
}

/// The `create:glue_effect` packet to the players tracking the chunk.
void _sendGlueEffect(
  World world,
  Pos pos,
  Direction direction,
  bool fullBlock,
) {
  final bus = ActuatorHosts.payloadBus;
  bus?.sendToTrackingAt('create:glue_effect', world.getId(), pos, {
    'pos': pos,
    'direction': direction,
    'fullBlock': fullBlock,
  });
}

