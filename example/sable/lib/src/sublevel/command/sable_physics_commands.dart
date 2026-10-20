// `dev.ryanhcode.sable.command.SablePhysicsCommands`:
//
//  * `/sable physics impulse <sub_level> linear <x> <y> <z> [global|local]`
//  * `/sable physics impulse <sub_level> angular <x> <y> <z> [global|local]`
//  * `/sable physics rotation <sub_level> add axis <x> <y> <z> <angle> [global|local]`
//  * `/sable physics rotation <sub_level> add entity <yaw> <pitch> [global|local]`
//  * `/sable physics rotation <sub_level> set axis <x> <y> <z> <angle>`
//  * `/sable physics rotation <sub_level> set entity <yaw> <pitch>`
//  * `/sable physics translation <sub_level> add <x> <y> <z> [global|local]`
//  * `/sable physics translation <sub_level> set <x> <y> <z>`
//
// Pure: no host imports beyond the model.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart' show ArgumentTypes, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_helper.dart';
import '../api/physics.dart';
import '../api/command/sable_command_state.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../system/physics_system.dart';
import 'command_support.dart';

/// Registers the `physics` branch under [sable].
void registerPhysicsCommands(CommandBuilder sable, SableCommandState state) {
  sable.sub(
    'physics',
    description: 'Applies impulses, rotations and translations to sub-levels',
    build: (physics) {
      physics.sub(
        'impulse',
        build: (impulse) => impulse.arg(
          'sub_level',
          ArgumentTypes.word,
          build: (sub) => sub
            ..sub(
              'linear',
              build: (linear) => _vec3Args(
                linear,
                (ctx, x, y, z, global) => _linearImpulse(ctx, state, x, y, z, global),
              ),
            )
            ..sub(
              'angular',
              build: (angular) => _vec3Args(
                angular,
                (ctx, x, y, z, global) => _angularImpulse(ctx, state, x, y, z, global),
              ),
            ),
        ),
      );

      physics.sub(
        'rotation',
        build: (rotation) {
          rotation.arg('sub_level', ArgumentTypes.word, build: (sub) {
            for (final add in [true, false]) {
              sub.sub(add ? 'add' : 'set', build: (mode) => _rotationMode(mode, state, add));
            }
          });
        },
      );

      physics.sub(
        'translation',
        build: (translation) => translation.arg(
          'sub_level',
          ArgumentTypes.word,
          build: (sub) => sub
            ..sub(
              'add',
              build: (add) => _vec3Args(
                add,
                (ctx, x, y, z, global) => _addTranslation(ctx, state, x, y, z, global),
              ),
            )
            ..sub(
              'set',
              build: (set) => set
                ..arg('x', ArgumentTypes.number(), build: (x) => x
                  ..arg('y', ArgumentTypes.number(), build: (y) => y
                    ..arg('z', ArgumentTypes.number(), runs: (ctx) {
                      final target = _single(ctx, state, 'sub_level');
                      final destination = Vector3d(ctx.number('x'), ctx.number('y'), ctx.number('z'));
                      final physics = _physics(ctx, state);
                      physics.getPipeline().teleport(
                        physics.getPhysicsHandle(target),
                        destination,
                        target.logicalPose.orientation(),
                      );
                      ctx.reply(
                        'Set the position of ${SableCommandHelper.describeSubLevels([target])} to '
                        '${_fmt(destination.x)}, ${_fmt(destination.y)}, ${_fmt(destination.z)}.',
                      );
                    })))),
        ),
      );
    },
  );
}

/// `x y z [global|local]` for the impulse and translation commands.
void _vec3Args(
  CommandBuilder builder,
  int Function(CommandContext ctx, double x, double y, double z, bool global) run,
) {
  builder.arg(
    'x',
    ArgumentTypes.number(),
    build: (x) => x
      ..arg('y', ArgumentTypes.number(), build: (y) => y
        ..arg('z', ArgumentTypes.number(), runs: (ctx) => run(
          ctx,
          ctx.number('x'),
          ctx.number('y'),
          ctx.number('z'),
          true,
        ), build: (z) {
          for (final global in [true, false]) {
            z.sub(global ? 'global' : 'local', runs: (ctx) => run(
              ctx,
              ctx.number('x'),
              ctx.number('y'),
              ctx.number('z'),
              global,
            ));
          }
        })),
  );
}

/// The `axis`/`entity` reference frames of `add`/`set`.
void _rotationMode(CommandBuilder mode, SableCommandState state, bool add) {
  mode.sub('axis', build: (axis) {
    axis.arg('x', ArgumentTypes.number(), build: (x) {
      x.arg('y', ArgumentTypes.number(), build: (y) {
        y.arg('z', ArgumentTypes.number(), build: (z) {
          z.arg('angle', ArgumentTypes.number(), build: (angle) {
            void run(CommandContext ctx, bool global) {
              final target = _single(ctx, state, 'sub_level');
              _rotate(
                ctx,
                state,
                target,
                Quaterniond()
                  ..fromAxisAngleDeg(
                    Vector3d(ctx.number('x'), ctx.number('y'), ctx.number('z')),
                    ctx.number('angle'),
                  ),
                add: add,
                global: global,
                describe: 'axis ${ctx.number('x')}, ${ctx.number('y')}, ${ctx.number('z')} '
                    'by ${ctx.number('angle')} degrees',
              );
            }

            angle.runs((ctx) => run(ctx, true));
            if (!add) return;
            angle.sub('global', runs: (ctx) => run(ctx, true));
            angle.sub('local', runs: (ctx) => run(ctx, false));
          });
        });
      });
    });
  });

  mode.sub('entity', build: (entity) {
    entity.arg('yaw', ArgumentTypes.number(), build: (yaw) {
      yaw.arg('pitch', ArgumentTypes.number(), build: (pitch) {
        void run(CommandContext ctx, bool global) {
          final target = _single(ctx, state, 'sub_level');
          _rotate(
            ctx,
            state,
            target,
            _rotationFromLook(ctx.number('yaw'), ctx.number('pitch')),
            add: add,
            global: global,
            describe: '${ctx.number('yaw')}, ${ctx.number('pitch')}',
          );
        }

        pitch.runs((ctx) => run(ctx, true));
        if (!add) return;
        pitch.sub('global', runs: (ctx) => run(ctx, true));
        pitch.sub('local', runs: (ctx) => run(ctx, false));
      });
    });
  });
}

ServerSubLevel _single(CommandContext ctx, SableCommandState state, String key) =>
    selectedSubLevel(ctx, state, key);

SubLevelPhysicsSystem _physics(CommandContext ctx, SableCommandState state) {
  try {
    return SableCommandHelper.requireSubLevelPhysicsSystem(containerOf(ctx, state));
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}

int _linearImpulse(
  CommandContext ctx,
  SableCommandState state,
  double x,
  double y,
  double z,
  bool global,
) {
  final physics = _physics(ctx, state);
  final subLevels = selectedSubLevels(ctx, state, 'sub_level', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  final impulse = Vector3d(x, y, z);
  for (final subLevel in subLevels) {
    final applied = global
        ? subLevel.logicalPose.transformNormalInverse(Vector3d.copy(impulse))
        : Vector3d.copy(impulse);
    physics.getPhysicsHandle(subLevel).applyLinearImpulse(applied);
  }

  ctx.reply(
    'Applied a ${global ? 'global' : 'local'} linear impulse of '
    '${_fmt(x)}, ${_fmt(y)}, ${_fmt(z)} to '
    '${SableCommandHelper.describeSubLevels(subLevels)}.',
  );
  return 0;
}

int _angularImpulse(
  CommandContext ctx,
  SableCommandState state,
  double x,
  double y,
  double z,
  bool global,
) {
  final physics = _physics(ctx, state);
  final subLevels = selectedSubLevels(ctx, state, 'sub_level', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  final impulse = Vector3d(x, y, z);
  for (final subLevel in subLevels) {
    final applied = global
        ? subLevel.logicalPose.transformNormalInverse(Vector3d.copy(impulse))
        : Vector3d.copy(impulse);
    physics.getPhysicsHandle(subLevel).applyAngularImpulse(applied);
  }

  ctx.reply(
    'Applied a ${global ? 'global' : 'local'} angular impulse of '
    '${_fmt(x)}, ${_fmt(y)}, ${_fmt(z)} to '
    '${SableCommandHelper.describeSubLevels(subLevels)}.',
  );
  return 0;
}

Quaterniond _rotationFromLook(double yaw, double pitch) => Quaterniond()
  ..rotateY(-yaw * math.pi / 180.0)
  ..rotateX(pitch * math.pi / 180.0);

int _rotate(
  CommandContext ctx,
  SableCommandState state,
  ServerSubLevel subLevel,
  Quaterniond orientation, {
  required bool add,
  required bool global,
  required String describe,
}) {
  final physics = _physics(ctx, state);
  final pose = subLevel.logicalPose;
  final mutable = subLevel.pose;

  if (add) {
    if (global) {
      mutable.orientation().premul(orientation);
    } else {
      mutable.orientation().mul(orientation);
    }
  } else {
    mutable.orientation().setFrom(orientation);
  }

  physics.getPipeline().teleport(
    physics.getPhysicsHandle(subLevel),
    pose.position(),
    pose.orientation(),
  );

  ctx.reply(
    '${add ? 'Added' : 'Set'} a ${global ? 'global' : 'local'} rotation of $describe to '
    '${SableCommandHelper.describeSubLevels([subLevel])}.',
  );
  return 0;
}

int _addTranslation(
  CommandContext ctx,
  SableCommandState state,
  double x,
  double y,
  double z,
  bool global,
) {
  final physics = _physics(ctx, state);
  final subLevels = selectedSubLevels(ctx, state, 'sub_level', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  for (final subLevel in subLevels) {
    final translation = Vector3d(x, y, z);
    final applied = global ? translation : subLevel.logicalPose.transformNormal(translation);
    physics.getPipeline().teleport(
      physics.getPhysicsHandle(subLevel),
      subLevel.logicalPose.position().add(applied),
      subLevel.logicalPose.orientation(),
    );
  }

  ctx.reply(
    'Translated ${SableCommandHelper.describeSubLevels(subLevels)} by '
    '${_fmt(x)}, ${_fmt(y)}, ${_fmt(z)} (${global ? 'global' : 'local'}).',
  );
  return 0;
}

String _fmt(double value) => value.toStringAsFixed(2);
