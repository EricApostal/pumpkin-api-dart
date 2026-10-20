// TEMPORARY PROBE - delete before finishing.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_api/pumpkin_api.dart' as api show FakePlayerActions;

import '../../common/host_bridge.dart' show BlockStates;
import '../../core/worlds.dart';
import '../../trains/support/runtime.dart' show Tr;
import 'wrench_probe.dart' show firstWorld;

Future<void> runTrackProbe(
  World world,
  int x,
  int y,
  int z,
  CommandContext ctx,
) async {
  final log = Tr.i.log;
  final pos = BlockPos(x: x, y: y, z: z);
  for (var i = 0; i < 40 && !world.isLoaded(pos: pos); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  log.info('TRACKPROBE world=${world.getId()} loaded=${world.isLoaded(pos: pos)}');

  final trackId = BlockStates.withProperties('create:track', {
    'shape': 'zo',
    'turn': 'false',
    'waterlogged': 'false',
  });
  log.info('TRACKPROBE trackId=$trackId');
  await world.setBlockState(
    pos: pos,
    state: trackId!,
    updateFlags: BlockUpdateFlags.normal,
  );
  final before = world.getBlockState(pos: pos);
  log.info('TRACKPROBE before=${before.blockName} ${before.properties}');

  final bot = FakePlayers.create(world, 'TrackProbe');
  api.FakePlayerActions(bot).moveTo(world, (x + .5, y.toDouble(), z + 1.5), yaw: 0, pitch: 0);
  log.info('TRACKPROBE look=${bot.lookDirection} yaw=${bot.getYaw()} pitch=${bot.getPitch()}');
  final stack = ItemStack.create(registryKey: 'create:track', count: 64);
  await bot.getInventory().setItemInHand(hand: Hand.right, item: stack);

  final changed1 = await bot.useItemOnBlock(pos, BlockDirection.up);
  final after1 = world.getBlockState(pos: pos);
  final held1 = bot.getInventory().getItemInHand(hand: Hand.right);
  log.info(
    'TRACKPROBE click1 changed=$changed1 after=${after1.blockName} '
    'held=${await held1?.getRegistryKey()} count=${await held1?.getCount()} '
    'comp=${held1?.customComponent('create:track_connecting_from')?.length}',
  );
  held1?.dispose();

  final endPos = BlockPos(x: x, y: y, z: z + 8);
  api.FakePlayerActions(bot).moveTo(world, (x + .5, y.toDouble(), z + 9.5), yaw: 0, pitch: 0);
  final changed2 = await bot.useItemOnBlock(endPos, BlockDirection.up);
  final held2 = bot.getInventory().getItemInHand(hand: Hand.right);
  log.info(
    'TRACKPROBE click2 changed=$changed2 held=${await held2?.getRegistryKey()} '
    'count=${await held2?.getCount()} '
    'comp=${held2?.customComponent('create:track_connecting_from')?.length}',
  );
  held2?.dispose();

  for (var dz = -1; dz <= 9; dz++) {
    final s = world.getBlockState(pos: BlockPos(x: x, y: y, z: z + dz));
    log.info('TRACKPROBE at z+$dz: ${s.blockName} ${s.properties}');
  }
  FakePlayers.remove(bot);
}
