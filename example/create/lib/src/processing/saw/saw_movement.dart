// `SawMovementBehaviour`: the saw on a contraption fells whole trees and hurts entities it runs
// into. `content/kinetics/saw/SawMovementBehaviour.java`.
import 'dart:async';

import '../../api/block_state.dart';
import '../../common/common.dart' hide pos;
import '../../contraptions/actors/actor_runtime.dart';
import '../../contraptions/actors/block_breaking_movement_behaviour.dart';
import '../../contraptions/core/level.dart';
import '../../contraptions/core/movement.dart';
import '../../common/host_bridge.dart';
import 'tree_cutter.dart';

/// The saw as a contraption actor.
class SawMovementBehaviour extends BlockBreakingMovementBehaviour {
  const SawMovementBehaviour();

  Direction _facing(MovementContext context) =>
      context.state.dir('facing') ?? Direction.north;

  @override
  bool isActive(MovementContext context) =>
      super.isActive(context) &&
      !VecHelper.isVecPointingTowards(
        context.relativeMotion,
        _facing(context).opposite,
      );

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final f = _facing(context);
    return (f.stepX * .65, f.stepY * .65, f.stepZ * .65);
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    await super.visitNewPosition(context, pos);
    final f = _facing(context);
    final facingVec = context.rotation((
      f.stepX.toDouble(),
      f.stepY.toDouble(),
      f.stepZ.toDouble(),
    ));
    final closest = Direction.nearest(facingVec.$1, facingVec.$2, facingVec.$3);
    if (closest.axis.isVertical && context.data.contains('BreakingPos')) {
      context.data.remove('BreakingPos');
      context.stall = false;
    }
  }

  @override
  bool canBreak(ContraptionLevel level, Pos breakingPos, BState state) =>
      super.canBreak(level, breakingPos, state) &&
      isSawable(state, (s, tag) => level.stateHasTag(s, tag));

  @override
  Future<void> onBlockBroken(
    MovementContext context,
    Pos pos,
    BState brokenState,
  ) async {
    if (brokenState.key == 'minecraft:leaves' ||
        brokenState.key.endsWith('_leaves')) {
      return;
    }

    final world = actors?.worldOf(context);
    if (world == null) return;

    final tree = findTree(
      stateAt: (p) => context.level.stateAt(p),
      hasTag: (s, tag) => context.level.stateHasTag(s, tag),
      height: 384,
      pos: pos,
      brokenState: brokenState,
    );
    if (tree.isEmpty) return;

    final futures = <Future<void>>[];
    tree.destroyBlocks((p) {
      futures.add(
        BlockHelper.destroyBlockWith(world, p, 1, (stack) async {
          await collectOrDropHost(context, stack);
        }),
      );
    });
    await Future.wait(futures);
  }

  /// No dynamic trees in this fork (`TreeCutter.canDynamicTreeCutFrom` is always false).
  @override
  bool shouldDestroyStartBlock(BState stateToBreak) => true;

  @override
  String? getDamageSourceKey() => 'create:mechanical_saw';
}
