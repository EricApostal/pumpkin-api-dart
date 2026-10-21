// TEMPORARY (DeferredEventDrainLatency): the write-cost rig for the deferred-event drain work.
//
// `create wbench <from> <to> <mode>` prices one plugin-initiated bulk write through
// `world.placeBlocks`, with and without the per-block block-added callback, and logs how many
// blocks the host actually changed. `create wbdump` prints the `placed` callbacks the plugin
// received since that write started, oldest first, each with its offset from the write's start.
//
// DELETE this file and its two call sites (`create_commands.dart` `_buildCreate`,
// `track_registration.dart` `onPlaced`) when the drain fix is finished.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/registry.dart';
import 'create_commands.dart';

/// `x,y,z@<micros since the write started>` per delivered `placed` callback, oldest first.
final List<String> wbDeliveries = [];

/// The write the deliveries above belong to; `null` before the first one.
Stopwatch? wbWatch;

/// Records one delivered `placed` callback, called from the track behaviour.
void wbRecord(CustomBlockPlacedEventData e) {
  final watch = wbWatch;
  if (watch == null) return;
  final p = e.pos;
  wbDeliveries.add('${p.x},${p.y},${p.z}@${watch.elapsedMicroseconds}us');
}

/// Registers the rig's commands.
void registerTempWriteBench(CommandBuilder c, InfraCommandState st) {
  final permission = CommandPermission.op(
    'create:command.create',
    description: 'Use /create',
  );
  c.sub(
    'wbench',
    description: 'TEMPORARY: price a plugin-initiated bulk write',
    permission: permission,
    build: (s) => s.arg(
      'from',
      ArgumentTypes.blockPos,
      build: (f) => f.arg(
        'to',
        ArgumentTypes.blockPos,
        build: (t) => t.arg(
          'mode',
          ArgumentTypes.word,
          runs: (ctx) => _wbench(ctx, st),
        ),
      ),
    ),
  );
  c.sub(
    'wbdump',
    description: 'TEMPORARY: print the delivery log',
    permission: permission,
    runs: (ctx) => _dump(ctx, st),
  );
}

/// The positions from [from] to [to] along the one axis they differ in.
List<Pos> _line(Pos from, Pos to) {
  final positions = <Pos>[];
  if (from.x != to.x) {
    final step = from.x <= to.x ? 1 : -1;
    for (var x = from.x; step > 0 ? x <= to.x : x >= to.x; x += step) {
      positions.add((x, from.y, from.z));
    }
  } else if (from.z != to.z) {
    final step = from.z <= to.z ? 1 : -1;
    for (var z = from.z; step > 0 ? z <= to.z : z >= to.z; z += step) {
      positions.add((from.x, from.y, z));
    }
  } else if (from.y != to.y) {
    final step = from.y <= to.y ? 1 : -1;
    for (var y = from.y; step > 0 ? y <= to.y : y >= to.y; y += step) {
      positions.add((from.x, y, from.z));
    }
  }
  return positions;
}

Future<void> _wbench(CommandContext ctx, InfraCommandState st) async {
  final world =
      ctx.sender.world() ??
      (throw CommandException('This command needs a world.'));
  final from = ctx.blockPos('from').toPos();
  final to = ctx.blockPos('to').toPos();
  final mode = ctx.string('mode');
  final positions = _line(from, to);
  if (positions.isEmpty) {
    ctx.reply('WBENCH empty range');
    return;
  }
  final blockKey = mode.startsWith('stone')
      ? 'minecraft:stone'
      : mode.startsWith('air') || mode == 'clear'
      ? 'minecraft:air'
      : 'create:track';
  // `TrackBlock.defaultState`: shape=zo, turn=false, waterlogged=false.
  final state = blockKey == 'create:track'
      ? BState(blockKey, {
          'shape': 'zo',
          'turn': 'false',
          'waterlogged': 'false',
        })
      : BState(blockKey);
  final id = stateIdOf(state);
  if (id == null) {
    st.log.warn('WBENCH no state for $blockKey');
    return;
  }
  final skip = mode.endsWith('skip') || mode == 'clear';
  final flags = skip
      ? BlockUpdateFlags.normal.union(const {BlockFlagsFlag.skipBlockAddedCallback})
      : BlockUpdateFlags.normal;
  for (final p in positions) {
    if (!world.isLoaded(pos: p.toBlockPos())) {
      throw CommandException('That position is not loaded ($p)');
    }
  }
  final changes = [
    for (final p in positions) BlockPlacementChange(p.toBlockPos(), id),
  ];
  wbDeliveries.clear();
  final watch = Stopwatch()..start();
  wbWatch = watch;
  final changed = await world.placeBlocks(changes, flags: flags);
  final micros = watch.elapsedMicroseconds;
  final line =
      'WBENCH $mode n=${positions.length} changed=$changed of '
      '${positions.length} write=${micros}us';
  st.log.info(line);
  ctx.reply(line);
  // The callbacks of a plugin-initiated write arrive after it returns, so read the log later.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 5), () {
      final deliveries = List<String>.of(wbDeliveries);
      final first = deliveries.isEmpty ? 'none' : deliveries.first;
      final last = deliveries.isEmpty ? 'none' : deliveries.last;
      st.log.info(
        'WBENCH $mode deliveries=${deliveries.length} first=$first last=$last',
      );
    }),
  );
}

void _dump(CommandContext ctx, InfraCommandState st) {
  final deliveries = List<String>.of(wbDeliveries);
  final line = 'WBENCH dump ${deliveries.length}: ${deliveries.join(' ')}';
  st.log.info(line);
  ctx.reply(line);
}