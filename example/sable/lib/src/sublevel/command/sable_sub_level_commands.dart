// `dev.ryanhcode.sable.command.SableSubLevelCommands`:
//
//  * `/sable name set <targets> <name>`
//  * `/sable name clear <targets>`
//  * `/sable name get <target>`
//  * `/sable teleport <targets> <x> <y> <z> [yaw pitch]`
//  * `/sable remove <targets>`
//
// Pure: no host imports beyond the model.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart' show ArgumentTypes, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../storage/sub_level_removal_reason.dart';
import '../system/physics_system.dart';
import 'command_support.dart';

/// Registers the `name`, `teleport` and `remove` branches under [sable].
void registerSubLevelCommands(CommandBuilder sable, SableCommandState state) {
  sable.sub(
    'name',
    description: 'Names or clears the name of sub-levels',
    build: (name) {
      name.sub(
        'set',
        build: (set) => set
          ..arg('targets', ArgumentTypes.word, build: (targets) => targets.arg(
            'name',
            ArgumentTypes.string,
            runs: (ctx) => _setName(ctx, state, ctx.string('name')),
          )),
      );
      name.sub(
        'clear',
        build: (clear) => clear.arg(
          'targets',
          ArgumentTypes.word,
          runs: (ctx) => _clearName(ctx, state),
        ),
      );
      name.sub(
        'get',
        build: (get) => get.arg(
          'target',
          ArgumentTypes.word,
          runs: (ctx) => _getName(ctx, state),
        ),
      );
    },
  );

  sable.sub(
    'teleport',
    description: 'Teleports sub-levels',
    build: (teleport) => teleport
      ..arg('targets', ArgumentTypes.word, build: (targets) => targets
        ..arg('x', ArgumentTypes.number(), build: (x) => x
          ..arg('y', ArgumentTypes.number(), build: (y) => y
            ..arg('z', ArgumentTypes.number(), runs: (ctx) => _teleport(ctx, state, false), build: (z) => z
              ..arg('yaw', ArgumentTypes.number(), build: (yaw) => yaw.arg(
                'pitch',
                ArgumentTypes.number(),
                runs: (ctx) => _teleport(ctx, state, true),
              )))))),
  );

  sable.sub(
    'remove',
    description: 'Removes sub-levels',
    build: (remove) => remove.arg(
      'targets',
      ArgumentTypes.word,
      runs: (ctx) => _remove(ctx, state),
    ),
  );
}

int _setName(CommandContext ctx, SableCommandState state, String name) {
  final subLevels = selectedSubLevels(ctx, state, 'targets', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  var modified = 0;
  for (final subLevel in subLevels) {
    if (subLevel.name != name) {
      subLevel.setName(name);
      modified++;
    }
  }

  if (modified == 0) throw CommandException(SableCommandError.noSubLevelsModified.message);

  ctx.reply(
    modified == 1
        ? 'Set the name of the sub-level to "$name".'
        : 'Set the name of $modified sub-levels to "$name".',
  );
  return modified;
}

int _clearName(CommandContext ctx, SableCommandState state) {
  final subLevels = selectedSubLevels(ctx, state, 'targets', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  var modified = 0;
  for (final subLevel in subLevels) {
    if (subLevel.name != null) {
      subLevel.setName(null);
      modified++;
    }
  }

  if (modified == 0) throw CommandException(SableCommandError.noSubLevelsModified.message);

  ctx.reply(
    modified == 1
        ? 'Cleared the name of the sub-level.'
        : 'Cleared the names of $modified sub-levels.',
  );
  return modified;
}

int _getName(CommandContext ctx, SableCommandState state) {
  final subLevel = selectedSubLevel(ctx, state, 'target');
  final name = subLevel.name;
  if (name == null) throw CommandException(SableCommandError.subLevelUnnamed.message);
  ctx.reply('The sub-level is named "$name".');
  return 1;
}

int _teleport(CommandContext ctx, SableCommandState state, bool withOrientation) {
  final container = containerOf(ctx, state);
  final SubLevelPhysicsSystem physics;
  try {
    physics = SableCommandHelper.requireSubLevelPhysicsSystem(container);
  } on StateError catch (error) {
    throw CommandException(error.message);
  }

  final targets = selectedSubLevels(ctx, state, 'targets', multiple: true);
  if (targets.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  final destination = Vector3d(
    ctx.number('x'),
    ctx.number('y'),
    ctx.number('z'),
  );

  Quaterniond? orientation;
  if (withOrientation) {
    final yaw = ctx.number('yaw');
    final pitch = ctx.number('pitch');
    orientation = Quaterniond()
      ..rotateY(-yaw * math.pi / 180.0)
      ..rotateX(pitch * math.pi / 180.0);
  }

  for (final ServerSubLevel target in targets) {
    final handle = physics.getPhysicsHandle(target);
    physics.getPipeline().resetVelocity(handle);
    physics.getPipeline().teleport(
      handle,
      destination,
      orientation ?? target.logicalPose.orientation(),
    );
  }

  if (withOrientation) {
    ctx.reply(
      'Teleported ${SableCommandHelper.describeSubLevels(targets)} to '
      '${_fmt(destination.x)}, ${_fmt(destination.y)}, ${_fmt(destination.z)} '
      'facing ${_fmt(ctx.number('yaw'))}, ${_fmt(ctx.number('pitch'))}.',
    );
  } else {
    ctx.reply(
      'Teleported ${SableCommandHelper.describeSubLevels(targets)} to '
      '${_fmt(destination.x)}, ${_fmt(destination.y)}, ${_fmt(destination.z)}.',
    );
  }
  return 1;
}

int _remove(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final targets = selectedSubLevels(ctx, state, 'targets', multiple: true);
  if (targets.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  final origin = container.getOrigin();
  for (final target in targets) {
    final plot = target.getPlot();
    container.removeSubLevel(
      plot.plotPos.$1 - origin.$1,
      plot.plotPos.$2 - origin.$2,
      SubLevelRemovalReason.removed,
    );
  }

  ctx.reply('Removed ${SableCommandHelper.describeSubLevels(targets)}.');
  return 1;
}

String _fmt(double value) => value.toStringAsFixed(2);
