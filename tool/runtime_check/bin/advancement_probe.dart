// TEMPORARY probe (delete after the award is proven): does the `SIGNAL` (`track_signal`)
// award actually fire on a live server? A fake player drives the real item path — click ground
// with `create:track` twice to lay a rail, click that rail with `create:track_signal` (stores the
// target), then click the ground beside it (the host places the signal block and the port awards)
// — and the probe reads the advancement back from the player's own progress.
//
// Run with a server that has create.wasm loaded, then `/advprobe signal`.
//
// Java `TrackTargetingBlockItem.java:170`: `if (type == EdgePointType.SIGNAL)` after a successful
// track-target selection. The port splits it across two host hooks: `itemUseFirst` stores the
// selection in the held stack (`_selectTarget`), `customBlockPlaced` writes the target into the
// block entity and awards (`_onTargetingBlockPlaced`). `/advancement grant` is NOT evidence — it
// bypasses the award site; this probe never calls it.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

void main() => runPlugin(AdvancementProbe());

final class AdvancementProbe extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'advancement_probe',
    version: '0.0.1',
    permissions: [Permissions.fakePlayers],
  );

  @override
  void onLoad(Context context) {
    final command = Command.create(names: ['advprobe'], description: 'advancement award probe');
    final action = CommandNode.argument(name: 'action', type: ArgumentTypes.word)
      ..execute((sender, server, args) async {
        final key = args.string('action');
        void log(String line) => logger.info('AP $key $line');
        try {
          for (final line in await probe(server, key, log)) {
            log(line);
          }
        } on Object catch (e) {
          log('FAIL: $e');
        }
        return 1;
      });
    command.then(node: action);
    context.registerCommand(command: command, permission: 'advancement_probe:advprobe');
  }
}

Future<List<String>> probe(
  Server server,
  String action,
  void Function(String) log,
) async {
  final world =
      server.getWorldByName(name: 'minecraft:overworld') ??
      server.getWorldByName(name: 'world') ??
      (throw StateError('no overworld'));
  final out = <String>[];
  if (action != 'signal') {
    out.add('usage: advprobe signal');
    return out;
  }

  final bot = FakePlayers.create(world, 'AdvProbe');
  try {
    Future<void> set(int x, int y, int z, String key) => world.setBlockState(
      pos: BlockPos(x: x, y: y, z: z),
      state: BlockRegistry.resolveState(key)!,
      updateFlags: {BlockFlagsFlag.notifyListeners},
    );

    Future<void> hold(String key) => bot.setItemInHand(
      hand: Hand.right,
      stack: ItemStack.create(registryKey: key, count: 1),
    );

    // A stone floor at y=100, clicked on its top face: the track and the signal land at y=101,
    // and every click stays inside the fake player's reach from (1.5, 102, 1.5). A click 8 blocks
    // away is a `BlockOutOfReach` host exception, not a probe result.
    for (var x = 0; x <= 2; x++) {
      for (var z = 0; z <= 1; z++) {
        await set(x, 100, z, 'minecraft:stone');
      }
    }
    FakePlayerActions(bot).moveTo(world, (1.5, 102.0, 1.5), yaw: 0, pitch: 0);
    log('floor(0,100,0)=${await _blockName(world, 0, 100, 0)}');
    out.add(
      'item ids: track=${ItemRegistries.host.idOf('create:track')} '
      'signal=${ItemRegistries.host.idOf('create:track_signal')}',
    );

    Future<void> click(String label, int x, int y, int z) async {
      final changed = await bot.useItemOnBlock(
        BlockPos(x: x, y: y, z: z),
        BlockDirection.up,
      );
      log(
        '$label changed=$changed clicked=${await _blockName(world, x, y, z)} '
        'above=${await _blockName(world, x, y + 1, z)} held=${await _held(bot)}',
      );
    }

    // 1. Lay a rail with the port's own item path: click ground (places a track at (0,101,0)),
    //    click that track (selects it), click ground again (lays the run to (2,101,0)). The two
    //    track blocks are what the signal needs a graph edge between.
    await hold('create:track');
    await click('rail1', 0, 100, 0);
    await click('rail2', 0, 101, 0);
    await click('rail3', 2, 100, 0);
    out.add(
      'rails=${await _blockName(world, 0, 101, 0)} / ${await _blockName(world, 2, 101, 0)}',
    );

    // 2. Click the rail at (2,101,0) with the signal item: `_selectTarget` stores the target.
    await hold('create:track_signal');
    await click('select', 2, 101, 0);

    // 3. Click the ground beside the rail: the host places `create:track_signal` at (1,101,1),
    //    `customBlockPlaced` fires and `_onTargetingBlockPlaced` awards.
    await click('place', 1, 100, 1);
    out.add(
      'signal block=${await _blockName(world, 1, 101, 1)} held=${await _held(bot)}',
    );

    final progress = bot.advancementProgress('create:track_signal');
    out.add(
      'signal_awarded=${progress?.done ?? false} '
      '(done=${progress?.done} awarded=${progress?.awardedCriteria})',
    );
  } finally {
    FakePlayers.remove(bot);
  }
  return out;
}

Future<String> _blockName(World world, int x, int y, int z) async {
  final id = world.getBlockStateId(pos: BlockPos(x: x, y: y, z: z));
  final name = BlockRegistry.fromStateId(id)?.name ?? '?';
  final props = BlockRegistry.stateFromId(id)?.propertyMap ?? const {};
  return '$name${props.isEmpty ? '' : props}';
}

Future<String> _held(Player bot) async {
  final stack = bot.getItemInHand(hand: Hand.right);
  if (stack == null) return 'empty';
  final key = await stack.getRegistryKey();
  final count = await stack.getCount();
  stack.dispose();
  return '$key x$count';
}