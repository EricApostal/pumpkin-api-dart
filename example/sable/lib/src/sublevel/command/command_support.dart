// `dev.ryanhcode.sable.command.SableCommandHelper`'s Dart side: resolving the
// sub-level selector arguments of a command from the sender's context.
//
// The only host calls here are the sender's position and rotation.
//
// create's block states are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart'
    show BlockPos, CommandContext, CommandException;

import 'package:create/src/api/block_state.dart' show BState;
import '../host/sub_level_host.dart';
import '../model/level_plot.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level_container.dart';
import '../math/vector.dart';
import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../api/command/sub_level_selector.dart';
import '../api/sub_level_raycast.dart';

/// The `@`-selectors the Java `SubLevelArgumentType` offers (`EXAMPLES` plus the
/// seven selectors of `SubLevelSelectorType`), for tab completion.
const List<String> subLevelSelectorSuggestions = [
  '@e',
  '@n',
  '@r',
  '@v',
  '@l',
  '@t',
  '@i',
];

/// Builds the selector context for [ctx] in [container].
///
/// The three host-provided lookups of [SubLevelTargetContext] are Java
/// `SubLevelTargetSelector.getSubLevels`, `SubLevelTargetSelector`'s `NEAREST`
/// branch and `SubLevelTargetSelector`'s `VIEWED` branch:
///
///  * `containing` is `Sable.HELPER.getContaining(level, source.getPosition())`;
///  * `projectedSourcePosition` is `Sable.HELPER.projectOutOfSubLevel`, which
///    `@n` compares against while the modifiers keep the raw position;
///  * `@v` picks 100 blocks along the sender's view
///    (`source.getEntity().pick(100.0, 1.0f, true)`) and takes the sub-level
///    containing the block that was hit. The plot's blocks are in memory, so
///    that ray is `SubLevelRaycast.pick` over the container instead of the
///    host's own block ray;
///  * `@t` is `Sable.HELPER.getTrackingSubLevel(entity)` in Java, the sub-level
///    the entity's collision was last resolved against
///    (`EntityMixin#sable$collideRedirect`). The port has no entity-collision
///    resolution yet (HOST GAP `entity-movement-sweep`), so the answer it can
///    give is the sub-level whose plot holds the sender -- the same sub-level
///    Java's tracking holds for an entity standing on a ship, and `null` for an
///    entity outside every plot, where Java has `null` too.
///
/// The sender's rotation drives `@v`; a sender that is not a player has no view,
/// so `@v` selects nothing for the console and for command blocks, as it does in
/// Java (`source.getEntity() == null`).
///
/// `Entity.pick`'s reach, in blocks.
const double _viewDistance = 100.0;

/// `Player.getEyeHeight` for a standing player.
///
/// The host exposes a player's position and rotation, not its eye height
/// (`player.wit` has no getter), and an eye inside the block it stands in is
/// close enough for a selector.
const double _playerEyeHeight = 1.62;

SubLevelTargetContext selectorContext(
  CommandContext ctx,
  SableCommandState state,
  ServerSubLevelContainer container,
) {
  final position = ctx.sender.position();
  final sourcePosition = position == null
      ? Vector3d()
      : Vector3d(position.$1, position.$2, position.$3);
  final containing = containingSubLevelOf(container, sourcePosition);
  final player = ctx.playerOrNull;

  ServerSubLevel? viewed;
  if (player != null) {
    final hit = SubLevelRaycast.pick(
      container,
      Vector3d(
        sourcePosition.x,
        sourcePosition.y + _playerEyeHeight,
        sourcePosition.z,
      ),
      SubLevelRaycast.lookVector(player.yaw, player.pitch),
      _viewDistance,
    );
    viewed = hit?.subLevel;
  }

  return SubLevelTargetContext(
    container: container,
    sourcePosition: sourcePosition,
    projectedOutOfSubLevel: containing == null
        ? sourcePosition
        : containing.logicalPose.transformPosition(Vector3d.copy(sourcePosition)),
    random: math.Random(state.random.nextInt(1 << 31)),
    trackingSubLevel: containing,
    viewedSubLevel: viewed,
    containingSubLevel: containing,
  );
}

/// The container of [ctx]'s world, or a command failure.
ServerSubLevelContainer containerOf(CommandContext ctx, SableCommandState state) {
  try {
    return SableCommandHelper.requireSubLevelContainer(state, ctx.sender.world());
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}

/// The sub-levels selected by the `sub_level`/`targets` argument [key].
List<ServerSubLevel> selectedSubLevels(
  CommandContext ctx,
  SableCommandState state,
  String key, {
  required bool multiple,
}) {
  final container = containerOf(ctx, state);
  final parser = multiple ? SubLevelArgumentType.subLevels : SubLevelArgumentType.singleSubLevel;
  try {
    final target = parser.parse(ctx.string(key));
    return target.resolve(selectorContext(ctx, state, container));
  } on SubLevelSelectorException catch (error) {
    throw CommandException(error.error.message);
  }
}

/// The single sub-level selected by [key].
ServerSubLevel selectedSubLevel(CommandContext ctx, SableCommandState state, String key) {
  final container = containerOf(ctx, state);
  try {
    final target = SubLevelArgumentType.singleSubLevel.parse(ctx.string(key));
    return target.resolveSingle(selectorContext(ctx, state, container));
  } on SubLevelSelectorException catch (error) {
    throw CommandException(error.error.message);
  }
}

/// The physics system of [ctx]'s world.
dynamic physicsSystemOf(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  try {
    return SableCommandHelper.requireSubLevelPhysicsSystem(container);
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}

/// The block position argument [key] as the model's tuple.
(int, int, int) blockPosOf(CommandContext ctx, String key) {
  final pos = ctx.blockPos(key);
  return (pos.x, pos.y, pos.z);
}

/// A `BlockPos` from the model tuple.
BlockPos toBlockPos((int, int, int) pos) => BlockPos(x: pos.$1, y: pos.$2, z: pos.$3);

/// The container's level view.
SableLevel levelOfContainer(SubLevelContainer container) => container.getLevel();

/// Sets the block at the plot-local position [local] (`EmbeddedPlotLevelAccessor`
/// offsets by the plot centre).
void setPlotBlock(LevelPlot plot, (int, int, int) local, BState state) {
  final center = plot.getCenterBlock();
  final global = (center.$1 + local.$1, center.$2 + local.$2, center.$3 + local.$3);
  final chunk = (global.$1 >> 4, global.$3 >> 4);
  if (plot.getChunk(plot.toLocal(chunk)) == null) {
    plot.newEmptyChunk(chunk);
  }
  plot.chunkHost.setBlock(global.$1, global.$2, global.$3, state.key);
}
