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
import '../model/server_sub_level.dart';
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
          ArgumentTypes.token,
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

  if (!_hasAssembledMass(container, blocks)) {
    throw CommandException('No blocks to assemble.');
  }

  final assembled = _countAssembledBlocks(container, blocks);
  final subLevel = SubLevelAssemblyHelper.assembleBlocks(container.getLevel(), from, blocks, bounds);
  _reportAssembly(ctx, subLevel, assembled);
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

  if (!_hasAssembledMass(container, result.blocks!)) {
    throw CommandException('No blocks to assemble.');
  }

  final assembled = _countAssembledBlocks(container, result.blocks!);
  final subLevel = SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    origin,
    result.blocks!,
    result.boundingBox!,
  );
  _reportAssembly(ctx, subLevel, assembled);
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

  final subLevel = SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    origin,
    blocks,
    BoundingBox3i.values(minX, minY, minZ, maxX, maxY, maxZ),
  );
  _reportAssembly(ctx, subLevel, blocks.length);
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

  if (!_hasAssembledMass(container, blocks)) {
    throw CommandException('No blocks to assemble.');
  }

  final assembled = _countAssembledBlocks(container, blocks);
  final subLevel = SubLevelAssemblyHelper.assembleBlocks(
    container.getLevel(),
    blocks.first,
    blocks,
    bounds,
  );
  _reportAssembly(ctx, subLevel, assembled);
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

/// Reports a finished assembly and fails only when the assembly really holds
/// nothing.
///
/// `SableAssembleCommands` ends every assemble branch with the same check: a
/// sub-level whose mass tracker is invalid has no solid blocks, so nothing was
/// assembled. A sub-level with **no** tracker is a different thing: the level
/// has no physics system, so nothing built one (`SubLevelPhysicsSystem
/// .onSubLevelAdded` is what calls `buildMassTracker`). The Java command has no
/// such case because a Java level always has a physics system; the port must
/// not report "No blocks to assemble" for it *after* the blocks were moved,
/// which reads as a failed assembly and hides a working one.
void _reportAssembly(CommandContext ctx, ServerSubLevel subLevel, int blockCount) {
  final tracker = subLevel.massTracker;
  if (tracker != null && tracker.isInvalid()) {
    throw CommandException('No blocks to assemble.');
  }

  ctx.reply('Assembled $blockCount blocks.');
  if (tracker == null) {
    ctx.reply(
      'HOST GAP: ${subLevel.level.dimensionId} has no physics system attached, so the '
      'sub-level has no mass tracker and no physics body.',
    );
  }
}

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

/// Shatters [blocks] into one sub-level per block
/// (`SableAssembleCommands.shatterBlocks`).
///
/// Java destroys the blocks that are **not** solid ("remove fragile blocks") and
/// then turns each remaining block into its own sub-level. The port had that
/// condition inverted — it destroyed every non-air block first and then found
/// nothing to assemble, so a shatter deleted the build and produced no
/// sub-levels at all.
int _shatterBlocks(SubLevelContainer container, Iterable<(int, int, int)> blocks) {
  final host = container.chunkHost;
  final list = blocks.toList();

  for (final pos in list) {
    final state = _stateAt(container, pos);
    if (!_isSolid(state)) host.setBlock(pos.$1, pos.$2, pos.$3, 'minecraft:air');
  }

  var shattered = 0;
  for (final anchor in list) {
    if (!_hasAssembledMass(container, [anchor])) continue;

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

/// `VoxelNeighborhoodState.isSolid`: whether the state takes part in physics.
///
/// The port's stand-in is the model's own default (`MassTracker.isSolid`, "not
/// air") until the plugin installs the block-property table.
bool _isSolid(BState state) => !state.isAir;

/// `hasAssembledMass` (`SableAssembleCommands.java:302-310`): whether a
/// selection holds at least one block that gives the assembled sub-level mass.
///
/// Java asks `PhysicsBlockPropertyHelper.getMass(level, pos, state) > 0.0`; the
/// port's default hooks are "not air" and mass 1.0 (`MassTracker.isSolid` /
/// `blockMass`), so a non-air block is a mass-bearing one until the plugin
/// installs the block-property table. Checking **before** the assembly is what
/// keeps an empty selection from moving blocks into a plot and leaving a
/// mass-less sub-level behind.
bool _hasAssembledMass(SubLevelContainer container, Iterable<(int, int, int)> blocks) =>
    blocks.any((pos) => _isSolid(_stateAt(container, pos)));

/// `countAssembledBlocks` (`SableAssembleCommands.java:284-292`): the blocks a
/// selection will actually move. The raw argument list is the whole selection
/// volume *including air*, so reporting its size claims far more was assembled
/// than really was.
int _countAssembledBlocks(SubLevelContainer container, Iterable<(int, int, int)> blocks) =>
    blocks.where((pos) => _isSolid(_stateAt(container, pos))).length;
