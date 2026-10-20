// `dev.ryanhcode.sable.command.SableSpawnCommands`:
//
//  * `/sable spawn jenga <height> [name]`
//  * `/sable spawn clone <sub_level> [name]`
//  * `/sable spawn sphere <radius> [block] [name]`
//  * `/sable spawn schematic <name>`   (host gap: no schematic loader)
//  * `/sable spawn joint_test`
//  * `/sable spawn slope_test [name]`
//  * `/sable spawn rope_test`
//  * `/sable spawn grid <sideLength> [block] [name]`
//  * `/sable spawn block [block] [name]`
//  * `/sable spawn platform <size> [block] [name]`
//
// Pure: no host imports beyond the model.
//
// create's block states and positions are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:pumpkin_api/pumpkin_api.dart'
    show ArgumentTypes, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../api/physics_constraint.dart';
import '../api/physics_pipeline.dart';
import '../api/physics_rope.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../model/server_level_plot.dart';
import '../model/server_sub_level.dart';
import '../model/sub_level_container.dart';
import '../system/physics_system.dart';
import 'command_support.dart';

/// `Blocks.STONE.defaultBlockState()`.
const BState _defaultMaterial = BState('minecraft:stone');

/// Registers the `spawn` branch under [sable].
void registerSpawnCommands(CommandBuilder sable, SableCommandState state) {
  sable.sub('spawn', description: 'Spawns test sub-levels', build: (spawn) {
    spawn.sub(
      'jenga',
      build: (jenga) => _named(jenga, (ctx, name) => _spawnJenga(ctx, state, name))
        ..arg('height', ArgumentTypes.integer(min: 1, max: 256), build: (height) =>
            _named(height, (ctx, name) => _spawnJenga(ctx, state, name))),
    );

    spawn.sub(
      'clone',
      build: (clone) => _named(clone, (ctx, name) => _clone(ctx, state, name))
        ..arg('sub_level', ArgumentTypes.word, build: (sub) =>
            _named(sub, (ctx, name) => _clone(ctx, state, name))),
    );

    spawn.sub(
      'sphere',
      build: (sphere) => sphere.arg(
        'radius',
        ArgumentTypes.integer(min: 2, max: 200),
        runs: (ctx) => _spawnSphere(ctx, state, _defaultMaterial, null),
        build: (radius) => radius.arg(
          'block',
          ArgumentTypes.word,
          runs: (ctx) => _spawnSphere(
            ctx,
            state,
            BState(ctx.string('block')),
            ctx.stringOrNull('name'),
          ),
          build: (block) => _named(
            block,
            (ctx, name) => _spawnSphere(ctx, state, BState(ctx.string('block')), name),
          ),
        ),
      ),
    );

    spawn.sub(
      'schematic',
      build: (schematic) => schematic.arg(
        'name',
        ArgumentTypes.word,
        runs: (ctx) => throw CommandException(
          'HOST GAP: /sable spawn schematic needs Sable\'s StructureTemplate loader '
          '(SchematicLoader) and the schematic folder; the Pumpkin plugin has neither, '
          'so no schematic can be read.',
        ),
      ),
    );

    spawn.sub('joint_test', runs: (ctx) => _spawnJointTest(ctx, state));

    spawn.sub(
      'slope_test',
      build: (slope) => _named(slope, (ctx, name) => _spawnSlopeTest(ctx, state, name)),
    );

    spawn.sub('rope_test', runs: (ctx) => _spawnRopeTest(ctx, state));

    spawn.sub(
      'grid',
      build: (grid) => grid.arg(
        'sideLength',
        ArgumentTypes.integer(min: 1, max: 32),
        runs: (ctx) => _spawnGrid(ctx, state, _defaultMaterial, null),
        build: (side) => side.arg(
          'block',
          ArgumentTypes.word,
          runs: (ctx) => _spawnGrid(
            ctx,
            state,
            BState(ctx.string('block')),
            ctx.stringOrNull('name'),
          ),
          build: (block) => _named(
            block,
            (ctx, name) => _spawnGrid(ctx, state, BState(ctx.string('block')), name),
          ),
        ),
      ),
    );

    spawn.sub(
      'block',
      build: (block) => _named(
        block,
        (ctx, name) => _spawnBlock(ctx, state, _defaultMaterial, name),
      )..arg(
        'block',
        ArgumentTypes.word,
        build: (material) => _named(
          material,
          (ctx, name) => _spawnBlock(ctx, state, BState(ctx.string('block')), name),
        ),
      ),
    );

    spawn.sub(
      'platform',
      build: (platform) => platform.arg(
        'size',
        ArgumentTypes.integer(min: 1, max: 32),
        runs: (ctx) => _spawnPlatform(ctx, state, _defaultMaterial, null),
        build: (size) => size.arg(
          'block',
          ArgumentTypes.word,
          runs: (ctx) => _spawnPlatform(
            ctx,
            state,
            BState(ctx.string('block')),
            ctx.stringOrNull('name'),
          ),
          build: (block) => _named(
            block,
            (ctx, name) => _spawnPlatform(ctx, state, BState(ctx.string('block')), name),
          ),
        ),
      ),
    );
  });
}

/// Adds the optional trailing `[name]` the Java `namedSpawnFinale` attaches.
CommandBuilder _named(CommandBuilder builder, int Function(CommandContext ctx, String? name) run) {
  builder.runs((ctx) => run(ctx, null));
  builder.arg('name', ArgumentTypes.string, runs: (ctx) => run(ctx, ctx.string('name')));
  return builder;
}

SubLevelContainer _container(CommandContext ctx, SableCommandState state) => containerOf(ctx, state);

Pose3d _poseAt(CommandContext ctx) {
  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final pose = Pose3d();
  pose.position().set(position.$1, position.$2, position.$3);
  return pose;
}

int _spawnJenga(CommandContext ctx, SableCommandState state, String? name) {
  final container = _container(ctx, state);
  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final height = ctx.integerOrNull('height') ?? 1;

  for (var yOffset = 0; yOffset < height; yOffset++) {
    final alongX = yOffset.isEven;

    for (var index = -1; index <= 1; index++) {
      final pose = Pose3d();
      pose.position().set(position.$1, position.$2, position.$3);
      if (index != 0) {
        if (alongX) {
          pose.position().x += index;
        } else {
          pose.position().z += index;
        }
      }
      pose.position().y += yOffset;

      final subLevel = container.allocateNewSubLevel(pose);
      subLevel.setName(name);
      final plot = subLevel.getPlot();
      plot.newEmptyChunk(plot.getCenterChunk());

      setPlotBlock(plot, (0, 0, 0), const BState('minecraft:spruce_planks'));
      for (var block = -1; block <= 1; block++) {
        final local = alongX ? (0, 0, block) : (block, 0, 0);
        setPlotBlock(
          plot,
          local,
          index == 0 ? const BState('minecraft:spruce_planks') : const BState('minecraft:oak_planks'),
        );
      }
      subLevel.updateLastPose();
    }
  }

  ctx.reply('Spawned jenga.');
  return 1;
}

int _clone(CommandContext ctx, SableCommandState state, String? name) {
  final container = _container(ctx, state);
  final toClone = selectedSubLevel(ctx, state, 'sub_level');

  final worldBounds = toClone.boundingBox;
  final height = worldBounds.maxY - worldBounds.minY;
  final tag = toClone.getPlot().save();

  final pose = Pose3d();
  pose.position().set(
    toClone.logicalPose.position().x,
    toClone.logicalPose.position().y + height * 1.2 + 2,
    toClone.logicalPose.position().z,
  );

  final subLevel = container.allocateNewSubLevel(pose);
  (subLevel.getPlot() as ServerLevelPlot).load(tag);
  subLevel.updateLastPose();
  if (name != null) subLevel.setName(name);

  ctx.reply('Cloned the sub-level.');
  return 1;
}

int _spawnSphere(CommandContext ctx, SableCommandState state, BState material, String? name) {
  final container = _container(ctx, state);
  final pose = _poseAt(ctx);
  final subLevel = container.allocateNewSubLevel(pose);
  subLevel.setName(name);

  final plot = subLevel.getPlot();
  final center = plot.getCenterChunk();
  final radius = ctx.integerOrNull('radius') ?? 2;
  final radiusChunks = (radius + 8) ~/ 16;
  for (var x = -radiusChunks; x <= radiusChunks; x++) {
    for (var z = -radiusChunks; z <= radiusChunks; z++) {
      plot.newEmptyChunk((center.$1 + x, center.$2 + z));
    }
  }

  final radiusSquared = radius * radius;
  for (var x = -radius; x <= radius; x++) {
    for (var z = -radius; z <= radius; z++) {
      for (var y = -radius; y <= radius; y++) {
        if (x * x + y * y + z * z <= radiusSquared) {
          setPlotBlock(plot, (x, y, z), material);
        }
      }
    }
  }
  subLevel.updateLastPose();

  ctx.reply('Spawned sphere.');
  return 1;
}

int _spawnGrid(CommandContext ctx, SableCommandState state, BState material, String? name) {
  final container = _container(ctx, state);
  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final sideLength = ctx.integerOrNull('sideLength') ?? 1;

  for (var x = 0; x < sideLength; x++) {
    for (var z = 0; z < sideLength; z++) {
      for (var y = 0; y < sideLength; y++) {
        final pose = Pose3d();
        pose.position().set(position.$1 + x * 2.1, position.$2 + y * 2.1, position.$3 + z * 2.1);

        final subLevel = container.allocateNewSubLevel(pose);
        subLevel.setName(name);
        final plot = subLevel.getPlot();
        plot.newEmptyChunk(plot.getCenterChunk());
        setPlotBlock(plot, (0, 0, 0), material);
        subLevel.updateLastPose();
      }
    }
  }

  ctx.reply('Spawned grid.');
  return 1;
}

int _spawnBlock(CommandContext ctx, SableCommandState state, BState material, String? name) {
  final container = _container(ctx, state);
  final subLevel = container.allocateNewSubLevel(_poseAt(ctx));
  subLevel.setName(name);
  final plot = subLevel.getPlot();
  plot.newEmptyChunk(plot.getCenterChunk());
  setPlotBlock(plot, (0, 0, 0), material);
  subLevel.updateLastPose();

  ctx.reply('Spawned block.');
  return 1;
}

int _spawnPlatform(CommandContext ctx, SableCommandState state, BState material, String? name) {
  final container = _container(ctx, state);
  final pose = _poseAt(ctx);
  final subLevel = container.allocateNewSubLevel(pose);
  subLevel.setName(name);

  final plot = subLevel.getPlot();
  final center = plot.getCenterChunk();
  final size = ctx.integerOrNull('size') ?? 1;
  final radiusChunks = (size + 8) ~/ 16;
  for (var x = -radiusChunks; x <= radiusChunks; x++) {
    for (var z = -radiusChunks; z <= radiusChunks; z++) {
      plot.newEmptyChunk((center.$1 + x, center.$2 + z));
    }
  }

  for (var x = -size; x <= size; x++) {
    for (var z = -size; z <= size; z++) {
      setPlotBlock(plot, (x, 0, z), material);
    }
  }
  subLevel.updateLastPose();

  if (subLevel is ServerSubLevel) {
    final physics = _physics(ctx, state);
    physics.getPipeline().teleport(
      physics.getPhysicsHandle(subLevel),
      subLevel.logicalPose.position(),
      pose.orientation(),
    );
  }

  ctx.reply('Spawned platform.');
  return 1;
}

int _spawnSlopeTest(CommandContext ctx, SableCommandState state, String? name) {
  final container = _container(ctx, state);
  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final physics = _physics(ctx, state);

  const gridSize = 9;
  final yawRange = math.pi / 2.0;
  final pitchRange = math.pi / 2.0;
  const rad = 3;
  const spacing = rad * 2 + 2;

  for (var xo = 0; xo <= gridSize; xo++) {
    for (var zo = 0; zo <= gridSize; zo++) {
      final pose = Pose3d();
      pose.position().set(position.$1, position.$2, position.$3);

      final subLevel = container.allocateNewSubLevel(pose);
      subLevel.setName(name);

      final plot = subLevel.getPlot();
      plot.newEmptyChunk(plot.getCenterChunk());
      const block = BState('minecraft:end_stone');
      for (var lx = -rad; lx < rad; lx++) {
        for (var lz = -rad; lz < rad; lz++) {
          setPlotBlock(plot, (lx, 0, lz), block);
        }
      }

      final destination = Vector3d(
        position.$1 + xo * spacing,
        position.$2,
        position.$3 + zo * spacing,
      );
      final orientation = Quaterniond()
        ..rotateY(xo * yawRange / gridSize)
        ..rotateX(zo * pitchRange / gridSize);

      if (subLevel is ServerSubLevel) {
        physics.getPipeline().teleport(
          physics.getPhysicsHandle(subLevel),
          destination,
          orientation,
        );
      }
    }
  }

  ctx.reply('Spawned slope_test.');
  return 1;
}

int _spawnJointTest(CommandContext ctx, SableCommandState state) {
  final container = _container(ctx, state);
  final physics = _physics(ctx, state);
  final pipeline = physics.getPipeline();
  if (pipeline is! ConstraintPipeline) {
    throw CommandException(SableCommandError.constraintsUnsupported.message);
  }

  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final poseA = Pose3d()..position().set(position.$1, position.$2, position.$3);
  final poseB = Pose3d()..position().set(position.$1, position.$2 + 1.0, position.$3);

  final subLevelA = container.allocateNewSubLevel(poseA);
  final subLevelB = container.allocateNewSubLevel(poseB);
  if (subLevelA is! ServerSubLevel || subLevelB is! ServerSubLevel) {
    throw CommandException('The container did not allocate server sub-levels.');
  }

  final plotA = subLevelA.getPlot();
  plotA.newEmptyChunk(plotA.getCenterChunk());
  setPlotBlock(plotA, (0, 0, 0), _defaultMaterial);

  final plotB = subLevelB.getPlot();
  plotB.newEmptyChunk(plotB.getCenterChunk());
  setPlotBlock(plotB, (0, 0, 0), _defaultMaterial);

  final centerA = plotA.getCenterBlock();
  final centerB = plotB.getCenterBlock();
  final config = RotaryConstraintConfiguration(
    Vector3d(centerA.$1 + 0.5, centerA.$2 + 2.0, centerA.$3 + 0.5),
    Vector3d(centerB.$1 + 0.5, centerB.$2.toDouble(), centerB.$3 + 0.5),
    Vector3d(0.0, 1.0, 0.0),
    Vector3d(0.0, 1.0, 0.0),
  );

  final handle = (pipeline as ConstraintPipeline).addConstraint(subLevelA, subLevelB, config);
  handle.setContactsEnabled(false);

  ctx.reply('Spawned joint_test.');
  return 1;
}

int _spawnRopeTest(CommandContext ctx, SableCommandState state) {
  final physics = _physics(ctx, state);
  final pipeline = physics.getPipeline();
  final position = ctx.sender.position() ?? (0.0, 0.0, 0.0);

  final points = [
    for (var i = 0; i < 10; i++) Vector3d(position.$1 + i, position.$2, position.$3),
  ];
  final rope = pipeline.addRope(RopePhysicsObject(points, 0.25));

  if (pipeline is RopeAttachable) {
    (pipeline as RopeAttachable).setAttachment(
      rope,
      RopeAttachmentPoint.start,
      Vector3d(position.$1, position.$2, position.$3),
    );
    ctx.reply('Spawned rope_test.');
  } else {
    ctx.reply(
      'Spawned rope_test without an anchor: this physics pipeline does not '
      'implement RopeAttachable, so the rope has no fixed end.',
    );
  }
  return 1;
}

SubLevelPhysicsSystem _physics(CommandContext ctx, SableCommandState state) {
  try {
    return SableCommandHelper.requireSubLevelPhysicsSystem(containerOf(ctx, state));
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}
