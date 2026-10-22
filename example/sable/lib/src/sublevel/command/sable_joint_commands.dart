// `dev.ryanhcode.sable.command.SableJointCommands`:
//
//  * `/sable debug joint add <subLevel1> <subLevel2> rotary <pos1> <pos2> <axis1> <axis2>`
//
// The four vectors are typed as one greedy string of twelve numbers, because the
// plugin's command builder parses one token per argument (`Vec3Argument` takes
// three in Brigadier).
//
// Pure: no host imports beyond the model.
import 'package:pumpkin_api/pumpkin_api.dart'
    show ArgumentTypes, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../api/physics_constraint.dart';
import '../math/vector.dart';
import 'command_support.dart';
import 'vec3_argument_absolute.dart';

/// Registers the `joint` branch under [debug].
void registerJointCommands(CommandBuilder debug, SableCommandState state) {
  debug.sub('joint', description: 'Creates joints between sub-levels', build: (joint) {
    joint.sub('add', build: (add) {
      add.arg(
        'subLevel1',
        ArgumentTypes.token,
        suggests: subLevelSelectorSuggestions,
        build: (first) {
          first.arg(
            'subLevel2',
            ArgumentTypes.token,
            suggests: subLevelSelectorSuggestions,
            build: (second) {
              second.sub('rotary', build: (rotary) {
                rotary.arg(
                  'vectors',
                  ArgumentTypes.greedyString,
                  runs: (ctx) => _addRotary(ctx, state),
                );
              });
            },
          );
        },
      );
    });
  });
}

int _addRotary(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final pipeline = SableCommandHelper.requireSubLevelPhysicsPipeline(container);

  final first = selectedSubLevels(ctx, state, 'subLevel1', multiple: true);
  final second = selectedSubLevels(ctx, state, 'subLevel2', multiple: true);
  if (first.isEmpty || second.isEmpty) {
    throw CommandException(SableCommandError.missingJointSubLevelTarget.message);
  }

  final vectors = parseAbsoluteVec3List(ctx.string('vectors'), 4);
  final config = RotaryConstraintConfiguration(
    Vector3d(vectors[0].$1, vectors[0].$2, vectors[0].$3),
    Vector3d(vectors[1].$1, vectors[1].$2, vectors[1].$3),
    Vector3d(vectors[2].$1, vectors[2].$2, vectors[2].$3),
    Vector3d(vectors[3].$1, vectors[3].$2, vectors[3].$3),
  );

  pipeline.addConstraint(first.first, second.first, config);
  ctx.reply('Created a rotary joint.');
  return 0;
}
