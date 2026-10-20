// `dev.ryanhcode.sable.command.SableConfigCommands`:
//
//  * `/sable debug config min_island_size <size>`
//  * `/sable debug config contact_spring_natural_frequency <hz>`
//  * `/sable debug config contact_spring_damping_ratio <ratio>`
//  * `/sable debug config solver_iterations <iterations>`
//  * `/sable debug config stabilization_iterations <iterations>`
//  * `/sable debug config pgs_iterations <iterations>`
//  * `/sable debug config substeps <substeps>`
//
// Pure: no host imports beyond the model.
import 'package:pumpkin_api/pumpkin_api.dart'
    show ArgumentTypes, CommandBuilder, CommandContext, CommandException;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../system/physics_system.dart';
import 'command_support.dart';

/// Registers the `config` branch under [debug].
void registerConfigCommands(CommandBuilder debug, SableCommandState state) {
  debug.sub('config', description: 'Edits the physics solver configuration', build: (config) {
    _intSetting(config, state, 'min_island_size', (physics, value) {
      physics.physicsConfig.minDynamicBodiesPerIsland = value;
    });
    _floatSetting(config, state, 'contact_spring_natural_frequency', (physics, value) {
      physics.physicsConfig.contactSpringFrequency = value;
    });
    _floatSetting(config, state, 'contact_spring_damping_ratio', (physics, value) {
      physics.physicsConfig.contactSpringDampingRatio = value;
    });
    _intSetting(config, state, 'solver_iterations', (physics, value) {
      physics.physicsConfig.solverIterations = value;
    });
    _intSetting(config, state, 'stabilization_iterations', (physics, value) {
      physics.physicsConfig.stabilizationIterations = value;
    });
    _intSetting(config, state, 'pgs_iterations', (physics, value) {
      physics.physicsConfig.pgsIterations = value;
    });
    _intSetting(config, state, 'substeps', (physics, value) {
      physics.physicsConfig.substepsPerTick = value;
    });
  });
}

void _intSetting(
  CommandBuilder config,
  SableCommandState state,
  String name,
  void Function(SubLevelPhysicsSystem physics, int value) apply,
) {
  config.sub(name, build: (setting) {
    setting.arg('value', ArgumentTypes.integer(min: 0), runs: (ctx) {
      final physics = _physics(ctx, state);
      final value = ctx.integer('value');
      apply(physics, value);
      physics.onConfigUpdated();
      ctx.reply('Set $name to $value.');
    });
  });
}

void _floatSetting(
  CommandBuilder config,
  SableCommandState state,
  String name,
  void Function(SubLevelPhysicsSystem physics, double value) apply,
) {
  config.sub(name, build: (setting) {
    setting.arg('value', ArgumentTypes.number(min: 0), runs: (ctx) {
      final physics = _physics(ctx, state);
      final value = ctx.number('value');
      apply(physics, value);
      physics.onConfigUpdated();
      ctx.reply('Set $name to $value.');
    });
  });
}

SubLevelPhysicsSystem _physics(CommandContext ctx, SableCommandState state) {
  try {
    return SableCommandHelper.requireSubLevelPhysicsSystem(containerOf(ctx, state));
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}
