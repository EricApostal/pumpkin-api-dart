// TEMPORARY PROBE - delete before finishing.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/wrenchable.dart';
import '../../common/host_bridge.dart' show BlockStates;
import '../../core/services.dart';
import '../../core/worlds.dart';

Future<void> runWrenchProbe(CreateServices services, World world, CommandContext ctx) async {
  final registry = services.find<WrenchRegistry>();
  ctx.reply(
    'PROBE registry=${registry?.blocks.length} shaft=${registry?.isWrenchable('create:shaft')} '
    'bearing=${registry?.isWrenchable('create:mechanical_bearing')}',
  );
  final spawn = world.getSpawnLocation().pos;
  ctx.reply(
    'PROBE world=${world.getId()} spawn=${spawn.x},${spawn.y},${spawn.z} '
    'chunk=${world.getChunk(x: spawn.x >> 4, z: spawn.z >> 4) != null}',
  );
  final pos = BlockPos(x: spawn.x, y: spawn.y + 2, z: spawn.z);
  final shaftId = BlockStates.withProperties('create:shaft', {'axis': 'y', 'waterlogged': 'false'});
  ctx.reply('PROBE shaftId=$shaftId');
  await world.setBlockState(pos: pos, state: shaftId!, updateFlags: BlockUpdateFlags.normal);
  final before = world.getBlockState(pos: pos);
  ctx.reply('PROBE before=${before.blockName} ${before.properties}');

  final bot = FakePlayers.create(world, 'WrenchProbe');
  FakePlayerActions(bot).moveTo(
    world,
    (pos.x + 0.5, pos.y.toDouble(), pos.z + 1.5),
    yaw: 0,
    pitch: 0,
  );
  final wrench = ItemStack.create(registryKey: 'create:wrench', count: 1);
  await bot.getInventory().setItemInHand(hand: Hand.right, item: wrench);
  final held = await bot.getInventory().getItemInHand(hand: Hand.right)?.getRegistryKey();
  ctx.reply('PROBE held=$held');
  final changed = await bot.useItemOnBlock(pos, BlockDirection.up);
  final after = world.getBlockState(pos: pos);
  ctx.reply('PROBE changed=$changed after=${after.blockName} ${after.properties}');

  // Sneak-wrench a bearing.
  final bearingId = BlockStates.defaultOf('create:mechanical_bearing');
  final bearingPos = BlockPos(x: pos.x + 3, y: pos.y, z: pos.z);
  await world.setBlockState(pos: bearingPos, state: bearingId!, updateFlags: BlockUpdateFlags.normal);
  FakePlayerActions(bot).moveTo(
    world,
    (bearingPos.x + 0.5, bearingPos.y.toDouble(), bearingPos.z + 1.5),
    yaw: 0,
    pitch: 0,
  );
  bot.setSneaking(true);
  final beforeB = world.getBlockState(pos: bearingPos);
  ctx.reply('PROBE bearing before=${beforeB.blockName} ${beforeB.properties}');
  final changedB = await bot.useItemOnBlock(bearingPos, BlockDirection.up);
  final afterB = world.getBlockState(pos: bearingPos);
  ctx.reply('PROBE bearing changed=$changedB after=${afterB.blockName} ${afterB.properties}');
  FakePlayers.remove(bot);
}

World? firstWorld(Worlds worlds) {
  for (final id in worlds.ids) {
    final w = worlds.byId(id);
    if (w != null) return w;
  }
  return null;
}
