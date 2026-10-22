// `dev.ryanhcode.sable.api.command.SableCommandHelper`: the container/system
// lookups and the sub-level description text every `/sable` command uses.
//
// The Java version builds translatable `Component`s; the port reports the same
// information as plain text (the plugin's command layer sends strings).
//
// Pure: no host imports.
import '../../model/server_sub_level.dart';
import '../../model/server_sub_level_container.dart';
import '../../model/sub_level_container.dart';
import 'sable_command_state.dart';
import '../physics_constraint.dart';
import '../../system/physics_system.dart';

/// The failures the `/sable` commands report.
enum SableCommandError {
  missingSubLevelContainer('commands.sable.helper.missing_sub_level_container'),
  missingPhysicsSystem('commands.sable.helper.missing_physics_system'),
  noSubLevels('commands.sable.fail.no_sub_levels'),
  notInsideSubLevel('commands.sable.fail.not_inside_sub_level'),
  noAxisForRotation('commands.sable.fail.no_axis_for_rotation'),
  noSubLevelsModified('commands.sable.fail.unmodified'),
  subLevelUnnamed('commands.sable.sub_level.get_name.failure_unnamed'),
  missingJointSubLevelTarget('commands.sable.joint.missing_sublevel_target'),
  /// Java's `requireSubLevelPhysicsPipeline` hands back whatever `getPipeline()`
  /// returned; only the port narrows it to a constraint pipeline, so this failure
  /// has no key in the mod's lang (`commands.sable.joint.unsupported` exists in
  /// neither `en_us.json` nor any Sable source).
  constraintsUnsupported(null),
  /// `/sable spawn rope_test` on an engine without rope support
  /// (`PhysicsPipelineFeature.rope`). Java has no such failure: its only engine
  /// always accepts `addRope`, so there is no key in the mod's lang either.
  ropeUnsupported(null);

  const SableCommandError(this.translationKey);

  /// The key the Java client translates, `null` when the failure is the port's own.
  final String? translationKey;

  /// The English text the port reports.
  String get message => switch (this) {
    SableCommandError.missingSubLevelContainer =>
      'This dimension has no sub-level container (is Sable installed on the server?).',
    SableCommandError.missingPhysicsSystem => 'The sub-level physics system is not running.',
    SableCommandError.noSubLevels => 'No sub-levels were found.',
    SableCommandError.notInsideSubLevel => 'You are not inside a sub-level.',
    SableCommandError.noAxisForRotation => 'A rotation axis is required.',
    SableCommandError.noSubLevelsModified => 'Nothing was modified.',
    SableCommandError.subLevelUnnamed => 'That sub-level has no name.',
    SableCommandError.missingJointSubLevelTarget => 'Both sub-levels of a joint are required.',
    SableCommandError.constraintsUnsupported =>
      'The physics pipeline of this dimension does not support constraints.',
    SableCommandError.ropeUnsupported =>
      'The physics pipeline of this dimension does not support ropes.',
  };
}

/// The lookups every `/sable` command needs.
abstract final class SableCommandHelper {
  /// `requireSubLevelContainer`: the container of the sender's level.
  static ServerSubLevelContainer requireSubLevelContainer(SableCommandState state, Object? world) {
    final level = state.levelOf(world);
    final container = SubLevelContainer.of(level);
    if (container is! ServerSubLevelContainer) {
      throw StateError(SableCommandError.missingSubLevelContainer.message);
    }
    return container;
  }

  /// `requireSubLevelPhysicsSystem(container)`.
  static SubLevelPhysicsSystem requireSubLevelPhysicsSystem(ServerSubLevelContainer container) {
    final physics = container.physics;
    if (physics is! SubLevelPhysicsSystem) {
      throw StateError(SableCommandError.missingPhysicsSystem.message);
    }
    return physics;
  }

  /// `requireSubLevelPhysicsPipeline`.
  static ConstraintPipeline requireSubLevelPhysicsPipeline(ServerSubLevelContainer container) {
    final pipeline = requireSubLevelPhysicsSystem(container).getPipeline();
    if (pipeline is! ConstraintPipeline) {
      throw StateError(SableCommandError.constraintsUnsupported.message);
    }
    return pipeline as ConstraintPipeline;
  }

  /// Describes a collection of sub-levels: their name for one, their count for
  /// several (`getResultComponentForSublevelCollection`).
  static String describeSubLevels(Iterable<ServerSubLevel> subLevels) {
    final list = subLevels.toList();
    if (list.length == 1) {
      return list.first.name ?? 'sub-level';
    }
    return '${list.length} sub-levels';
  }

  /// The sub-level's display name, falling back to its UUID.
  static String displayName(ServerSubLevel subLevel) => subLevel.name ?? subLevel.uniqueId;

  /// The clickable `/execute in … run tp` line the Java command prints in the
  /// hover text of a position.
  static String teleportSuggestion(String dimensionId, double x, double y, double z) =>
      '/execute in $dimensionId run tp @s ${x.toStringAsFixed(2)} '
      '${y.toStringAsFixed(2)} ${z.toStringAsFixed(2)}';
}
