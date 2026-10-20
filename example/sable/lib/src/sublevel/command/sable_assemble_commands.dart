// `dev.ryanhcode.sable.command.SableAssembleCommands`:
//
//  * `/sable assemble area <from> <to>`
//  * `/sable assemble connected [from] [capacity]`
//  * `/sable assemble sphere <radius> [origin]`
//  * `/sable assemble cube <range> [origin]`
//  * `/sable assemble shatter sub_level <sub_level>`
//  * `/sable assemble shatter connected [from] [capacity]`
//  * `/sable assemble shatter sphere <radius> [origin]`
//  * `/sable assemble shatter cube <range> [origin]`
//  * `/sable assemble shatter area <from> <to>`
//
// Pure: no host imports beyond the model.
//
// create's block states are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:pumpkin_api/pumpkin_api.dart'
    show ArgumentTypes, BlockPos, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_state.dart';
import '../api/sub_level_assembly_helper.dart';
import '../math/bounding_box.dart';
import '../model/sub_level_container.dart';
import 'command_support.dart';

/// `DEFAULT_CONNECTED_ASSEMBLY_CAPACITY`.
const int defaultConnectedAssemblyCapacity = 256000;

/// Registers the `assemble` branch under [sable].
void registerAssembleCommands(CommandBuilder sable, SableCommandState state) {
  sable.sub('assemble', description: 'Assembles and shatters sub-levels', build: (assemble) {
    assemble.sub(
      'area',
      build: (area) => area.arg('from', ArgumentTypes.blockPos, build: (from) => from.arg(
        'to',
        ArgumentTypes.blockPos,
        runs: (ctx) => _assembleArea(ctx, state),
      )),
    );

    assemble.sub(
      'connected',
      runs: (ctx) => _assembleConnected(ctx, state, _belowSender(ctx), defaultConnectedAssemblyCapacity),
      build: (connected) => connected.arg(
        'from',
        ArgumentTypes.blockPos,
        runs: (ctx) => _assembleConnected(
          ctx,
          state,
          blockPosOf(ctx, 'from'),
          defaultConnectedAssemblyCapacity,
        ),
        build: (from) => from.arg(
          'capacity',
          ArgumentTypes.integer(min: 1, max: defaultConnectedAssemblyCapacity * 100),
          runs: (ctx) => _assembleConnected(ctx, state, blockPosOf(ctx, 'from'), ctx.integer('capacity')),
        ),
      ),
    );

    assemble.sub(
      'sphere',
      build: (sphere) => sphere.arg(
        'radius',
        ArgumentTypes.integer(min: 0, max: 256),
        runs: (ctx) => _assembleSphere(ctx, state, _senderPos(ctx), ctx.integer('radius')),
        build: (radius) => radius.arg(
          'origin',
          ArgumentTypes.blockPos,
          runs: (ctx) => _assembleSphere(ctx, state, blockPosOf(ctx, 'origin'), ctx.integer('radius')),
        ),
      ),
    );

    assemble.sub(
      'cube',
      build: (cube) => cube.arg(
        'range',
        ArgumentTypes.integer(min: 0, max: 256),
        runs: (ctx) => _assembleCube(ctx, state, _senderPos(ctx), ctx.integer('range')),
        build: (range) => range.arg(
          'origin',
          ArgumentTypes.blockPos,
          runs: (ctx) => _assembleCube(ctx, state, blockPosOf(ctx, 'origin'), ctx.integer('range')),
        ),
      ),
    );

    assemble.sub('shatter', build: (shatter) {
      shatter.sub(
        'sub_level',
        build: (sub) => sub.arg(
          'sub_level',
          ArgumentTypes.word,
          runs: (ctx) => _shatterSubLevel(ctx, state),
        ),
      );

      shatter.sub(
        'connected',
        runs: (ctx) => _shatterConnected(ctx, state, _belowSender(ctx), defaultConnectedAssemblyCapacity),
        build: (connected) => connected.arg(
          'from',
          ArgumentTypes.blockPos,
          runs: (ctx) => _shatterConnected(
            ctx,
            state,
            blockPosOf(ctx, 'from'),
            defaultConnectedAssemblyCapacity,
          ),
          build: (from) => from.arg(
            'capacity',
            ArgumentTypes.integer(min: 1, max: defaultConnectedAssemblyCapacity * 100),
            runs: (ctx) => _shatterConnected(ctx, state, blockPosOf(ctx, 'from'), ctx.integer('capacity')),
          ),
        ),
      );

      shatter.sub(
        'sphere',
        build: (sphere) => sphere.arg(
          'radius',
          ArgumentTypes.integer(min: 0, max: 128),
          runs: (ctx) => _shatterSphere(ctx, state, _senderPos(ctx), ctx.integer('radius')),
          build: (radius) => radius.arg(
            'origin',
            ArgumentTypes.blockPos,
            runs: (ctx) => _shatterSphere(ctx, state, blockPosOf(ctx, 'origin'), ctx.integer('radius')),
          ),
        ),
      );

      shatter.sub(
        'cube',
        build: (cube) => cube.arg(
          'range',
          ArgumentTypes.integer(min: 0, max: 128),
          runs: (ctx) => _shatterCube(ctx, state, _senderPos(ctx), ctx.integer('range')),
          build: (range) => range.arg(
            'origin',
            ArgumentTypes.blockPos,
            runs: (ctx) => _shatterCube(ctx, state, blockPosOf(ctx, 'origin'), ctx.integer('range')),
          ),
        ),
      );

      shatter.sub(
        'area',
        build: (area) => area.arg('from', ArgumentTypes.blockPos, build: (from) => from.arg(
          'to',
          ArgumentTypes.blockPos,
          runs: (ctx) => _shatterArea(ctx, state),
        )),
      );
    });
  });
}

(int, int, int) _senderPos(CommandContext ctx) {
  final position = ctx.sender.position();
  if (position == null) throw CommandException('This command needs a position.');
  return (position.$1.floor(), position.$2.floor(), position.$3.floor());
}

(int, int, int) _belowSender(CommandContext ctx) {
  final pos = _senderPos(ctx);
  return (pos.$1, pos.$2 - 1, pos.$3);
}

(int, int, int) _fromBlockPos(BlockPos pos) => (pos.x, pos.y, pos.z);

int _assembleArea(CommandContext ctx, SableCommandState state) {
  final from = _fromBlockPos(ctx.blockPos('from'));
  final to = _fromBlockPos(ctx.blockPos('to'));
  final container = containerOf(ctx, state);
  final blocks = _blocksBetween(from, to);

  final bounds = BoundingBox3i.values(
    math.min(from.$1, to.$1) - 1,
    math.min(from.$2, to.$2) - 1,
    math.min(from.$3, to.$3) - 1,
    math.max(from.$1, to.$1) + 1,
    math.max(from.$2, to.$2) + 1,
    math.max(from.$3, to.$3) + 1,
  );

  final subLevel = SubLevelAssemblyHelper.assembleBlocks(container.getLevel(), from, blocks, bounds);
  if (subLevel.massTracker?.isInvalid() ?? true) {
    throw CommandException('No blocks to assemble.');
  }

  ctx.reply('Assembled ${blocks.length} blocks.');
  return 1;
}

int _assembleConnected(CommandContext ctx, SableCommandState state, (int, int, int) origin, int capacity) {
  final container = containerOf(ctx, state);
  final result = SubLevelAssemblyHelper.gatherConnectedBlocks(
    origin,
    container.getLevel(),
    capacity,
    null,
  );

  if (result.assemblyState != GatherState.success) {
    throw CommandException(_gatherFailure(result.assemblyState, capacity));
  }

  SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    origin,
    result.blocks!,
    result.boundingBox!,
  );
  ctx.reply('Assembled ${result.blocks!.length} blocks.');
  return 1;
}

int _assembleSphere(CommandContext ctx, SableCommandState state, (int, int, int) origin, int radius) {
  final container = containerOf(ctx, state);
  final radiusSquared = radius * radius;

  final blocks = <(int, int, int)>{};
  var minX = 1 << 31, minY = 1 << 31, minZ = 1 << 31;
  var maxX = -(1 << 31), maxY = -(1 << 31), maxZ = -(1 << 31);

  for (var x = -radius; x <= radius; x++) {
    for (var y = -radius; y <= radius; y++) {
      for (var z = -radius; z <= radius; z++) {
        if (x * x + y * y + z * z > radiusSquared) continue;
        final pos = (origin.$1 + x, origin.$2 + y, origin.$3 + z);
        if (_stateAt(container, pos).isAir) continue;

        blocks.add(pos);
        minX = math.min(minX, pos.$1);
        minY = math.min(minY, pos.$2);
        minZ = math.min(minZ, pos.$3);
        maxX = math.max(maxX, pos.$1);
        maxY = math.max(maxY, pos.$2);
        maxZ = math.max(maxZ, pos.$3);
      }
    }
  }

  if (blocks.isEmpty) throw CommandException('No blocks to assemble.');

  SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    origin,
    blocks,
    BoundingBox3i.values(minX, minY, minZ, maxX, maxY, maxZ),
  );
  ctx.reply('Assembled ${blocks.length} blocks.');
  return 1;
}

int _assembleCube(CommandContext ctx, SableCommandState state, (int, int, int) origin, int range) {
  final container = containerOf(ctx, state);
  final from = (origin.$1 - range, origin.$2 - range, origin.$3 - range);
  final to = (origin.$1 + range, origin.$2 + range, origin.$3 + range);
  final blocks = _blocksBetween(from, to);

  final bounds = BoundingBox3i.values(
    from.$1 - 1,
    from.$2 - 1,
    from.$3 - 1,
    to.$1 + 1,
    to.$2 + 1,
    to.$3 + 1,
  );

  final subLevel = SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    blocks.first,
    blocks,
    bounds,
  );
  if (subLevel.massTracker?.isInvalid() ?? true) {
    throw CommandException('No blocks to assemble.');
  }

  ctx.reply('Assembled ${blocks.length} blocks.');
  return 1;
}

int _shatterSubLevel(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final targets = selectedSubLevels(ctx, state, 'sub_level', multiple: true);
  if (targets.isEmpty) throw CommandException('No sub-levels were found.');

  var blocksShattered = 0;
  var subLevelsShattered = 0;

  for (final target in targets) {
    final bounds = target.getPlot().getBoundingBox();
    final solid = _solidBlocks(container, bounds);
    if (solid.length <= 1) continue;

    blocksShattered += _shatterBlocks(container, solid);
    subLevelsShattered++;
  }

  if (subLevelsShattered == 0) {
    throw CommandException('That sub-level only contains a single block.');
  }

  ctx.reply(
    'Shattered $subLevelsShattered sub-level${subLevelsShattered == 1 ? '' : 's'} '
    'into $blocksShattered blocks.',
  );
  return blocksShattered;
}

int _shatterConnected(CommandContext ctx, SableCommandState state, (int, int, int) origin, int capacity) {
  final container = containerOf(ctx, state);
  final result = SubLevelAssemblyHelper.gatherConnectedBlocks(
    origin,
    container.getLevel(),
    capacity,
    null,
  );

  if (result.assemblyState != GatherState.success) {
    throw CommandException(_gatherFailure(result.assemblyState, capacity));
  }

  final shattered = _shatterBlocks(container, result.blocks!);
  if (shattered == 0) throw CommandException('No blocks to shatter.');
  ctx.reply('Shattered $shattered blocks.');
  return shattered;
}

int _shatterSphere(CommandContext ctx, SableCommandState state, (int, int, int) origin, int radius) {
  final container = containerOf(ctx, state);
  final radiusSquared = radius * radius;
  final blocks = <(int, int, int)>[];

  for (var x = -radius; x <= radius; x++) {
    for (var y = -radius; y <= radius; y++) {
      for (var z = -radius; z <= radius; z++) {
        if (x * x + y * y + z * z > radiusSquared) continue;
        blocks.add((origin.$1 + x, origin.$2 + y, origin.$3 + z));
      }
    }
  }

  final shattered = _shatterBlocks(container, blocks);
  if (shattered == 0) throw CommandException('No blocks to shatter.');
  ctx.reply('Shattered $shattered blocks.');
  return shattered;
}

int _shatterCube(CommandContext ctx, SableCommandState state, (int, int, int) origin, int range) {
  final container = containerOf(ctx, state);
  final blocks = _blocksBetween(
    (origin.$1 - range, origin.$2 - range, origin.$3 - range),
    (origin.$1 + range, origin.$2 + range, origin.$3 + range),
  );

  final shattered = _shatterBlocks(container, blocks);
  if (shattered == 0) throw CommandException('No blocks to shatter.');
  ctx.reply('Shattered $shattered blocks.');
  return shattered;
}

int _shatterArea(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final from = _fromBlockPos(ctx.blockPos('from'));
  final to = _fromBlockPos(ctx.blockPos('to'));
  final shattered = _shatterBlocks(container, _blocksBetween(from, to));
  if (shattered == 0) throw CommandException('No blocks to shatter.');
  ctx.reply('Shattered $shattered blocks.');
  return shattered;
}

String _gatherFailure(GatherState state, int capacity) => switch (state) {
  GatherState.tooManyBlocks => 'Too many blocks: the limit is $capacity.',
  GatherState.noBlocks => 'No blocks to assemble.',
  GatherState.success => '',
};

/// Every block position between the two corners, inclusive.
List<(int, int, int)> _blocksBetween((int, int, int) from, (int, int, int) to) => [
  for (var x = math.min(from.$1, to.$1); x <= math.max(from.$1, to.$1); x++)
    for (var y = math.min(from.$2, to.$2); y <= math.max(from.$2, to.$2); y++)
      for (var z = math.min(from.$3, to.$3); z <= math.max(from.$3, to.$3); z++) (x, y, z),
];

/// The non-air blocks of [bounds] in the plot yard.
List<(int, int, int)> _solidBlocks(SubLevelContainer container, BoundingBox3ic bounds) => [
  for (var x = bounds.minX; x <= bounds.maxX; x++)
    for (var y = bounds.minY; y <= bounds.maxY; y++)
      for (var z = bounds.minZ; z <= bounds.maxZ; z++)
        if (!_stateAt(container, (x, y, z)).isAir) (x, y, z),
];

BState _stateAt(SubLevelContainer container, (int, int, int) pos) =>
    SubLevelAssemblyHelper.blockHostOf(container.getLevel())
        .blockStateAt(pos.$1, pos.$2, pos.$3);

/// Shatters [blocks] into one sub-level per block.
int _shatterBlocks(SubLevelContainer container, Iterable<(int, int, int)> blocks) {
  final host = container.chunkHost;
  final list = blocks.toList();

  // Remove the fragile blocks first.
  for (final pos in list) {
    if (_stateAt(container, pos).isAir) continue;
    host.setBlock(pos.$1, pos.$2, pos.$3, 'minecraft:air');
  }

  var shattered = 0;
  for (final anchor in list) {
    final state = _stateAt(container, anchor);
    if (state.isAir) continue;

    final bounds = BoundingBox3i.values(
      anchor.$1 - 1,
      anchor.$2 - 1,
      anchor.$3 - 1,
      anchor.$1 + 1,
      anchor.$2 + 1,
      anchor.$3 + 1,
    );
    SubLevelAssemblyHelper.assembleBlocks(container.getLevel(), anchor, [anchor], bounds);
    shattered++;
  }
  return shattered;
}
