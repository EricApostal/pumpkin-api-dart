// `DrillMovementBehaviour`: the drill on a contraption grinds through blocks and hurts entities.
// `content/kinetics/drill/DrillMovementBehaviour.java`.
import '../../api/block_state.dart';
import '../../common/common.dart' hide pos;
import '../../contraptions/actors/block_breaking_movement_behaviour.dart';
import '../../contraptions/core/level.dart';
import '../../contraptions/core/movement.dart';

/// The drill as a contraption actor.
class DrillMovementBehaviour extends BlockBreakingMovementBehaviour {
  const DrillMovementBehaviour();

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
  bool canBreak(ContraptionLevel level, Pos breakingPos, BState state) =>
      super.canBreak(level, breakingPos, state) &&
      !level.stateCollisionEmpty(state) &&
      !level.stateHasTag(state, 'create:tracks');

  @override
  String? getDamageSourceKey() => 'create:mechanical_drill';
}
