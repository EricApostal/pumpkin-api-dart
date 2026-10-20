// `dev.ryanhcode.sable.command.SableCommandHelper`'s Dart side: resolving the
// sub-level selector arguments of a command from the sender's context.
//
// Pure: no host imports beyond the model.
//
// create's block states are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart'
    show BlockPos, CommandContext, CommandException, Uuid;

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

/// Builds the selector context for [ctx] in [container].
SubLevelTargetContext selectorContext(
  CommandContext ctx,
  SableCommandState state,
  ServerSubLevelContainer container,
) {
  final position = ctx.sender.position();
  final sourcePosition = position == null
      ? Vector3d()
      : Vector3d(position.$1, position.$2, position.$3);
  final player = ctx.playerOrNull;
  final playerId = player == null ? null : uuidToString(player.getId());

  final containing = container.getPlot(
        sourcePosition.x.floor() >> 4,
        sourcePosition.z.floor() >> 4,
      )?.getSubLevel();

  return SubLevelTargetContext(
    container: container,
    sourcePosition: sourcePosition,
    random: math.Random(state.random.nextInt(1 << 31)),
    trackingSubLevel: playerId == null ? null : state.trackingSubLevel?.call(playerId),
    viewedSubLevel: playerId == null ? null : state.viewedSubLevel?.call(playerId),
    containingSubLevel: containing is ServerSubLevel ? containing : null,
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

/// Formats a host [Uuid] the way Minecraft's `UUID.toString` does.
String uuidToString(Uuid uuid) {
  String hex(int value, int digits) =>
      value.toUnsigned(64).toRadixString(16).padLeft(digits, '0').substring(16 - digits);
  final high = hex(uuid.high, 16);
  final low = hex(uuid.low, 16);
  return '${high.substring(0, 8)}-${high.substring(8, 12)}-${high.substring(12, 16)}-'
      '${low.substring(0, 4)}-${low.substring(4, 16)}';
}
