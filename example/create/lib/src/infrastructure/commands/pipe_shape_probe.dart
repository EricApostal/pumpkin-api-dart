// TEMPORARY PROBE - delete before finishing.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart' show BlockStates;

/// Places every pipe-like block and reports the shapes the host registered for it, plus whether
/// a ray along the player's cursor path hits the pipe.
Future<void> runPipeShapeProbe(World world, CommandContext ctx) async {
  final spawn = world.getSpawnLocation().pos;
  var x = spawn.x + 4;
  final y = spawn.y + 3;
  final z = spawn.z;

  String fmt(Iterable<BoundingBox> boxes) => boxes
      .map(
        (b) => '[${b.min.x.toStringAsFixed(3)},${b.min.y.toStringAsFixed(3)},'
            '${b.min.z.toStringAsFixed(3)}..${b.max.x.toStringAsFixed(3)},'
            '${b.max.y.toStringAsFixed(3)},${b.max.z.toStringAsFixed(3)}]',
      )
      .join(' ');

  for (final (key, props) in [
    ('create:fluid_pipe', {'north': 'true', 'south': 'true', 'up': 'false', 'down': 'false', 'east': 'false', 'west': 'false'}),
    ('create:glass_fluid_pipe', {'axis': 'z'}),
    ('create:smart_fluid_pipe', {'face': 'wall', 'facing': 'south'}),
    ('create:fluid_valve', {'facing': 'up', 'axis_along_first': 'true', 'enabled': 'false'}),
    ('create:encased_fluid_pipe', {'north': 'true', 'south': 'true', 'up': 'false', 'down': 'false', 'east': 'false', 'west': 'false'}),
    ('create:mechanical_pump', {'facing': 'north'}),
  ]) {
    final id = BlockStates.withProperties(key, props);
    if (id == null) {
      ctx.reply('PIPEPROBE $key: no state');
      x += 2;
      continue;
    }
    final pos = BlockPos(x: x, y: y, z: z);
    await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
    final state = world.getBlockState(pos: pos);
    ctx.reply(
      'PIPEPROBE $key outline=${state.outlineShapes.length} '
      'collision=${state.collisionShapes.length} '
      'o=${fmt(state.outlineShapes)} c=${fmt(state.collisionShapes)}',
    );
    // The player's cursor: from 3 blocks away towards the block centre, offset 0.2 off axis (a
    // 0.25-voxel hairline core would miss).
    final hit = world.rayTraceBlock(
      start: (x + 0.5, y + 0.5 + 0.2, z + 3.0),
      end: (x + 0.5, y + 0.5 + 0.2, z + 0.5),
      includeFluids: false,
    );
    ctx.reply(
      'PIPEPROBE $key ray=${hit == null ? 'MISS' : '${hit.pos.x},${hit.pos.y},${hit.pos.z} face=${hit.face.name}'}',
    );
    x += 2;
  }
}
