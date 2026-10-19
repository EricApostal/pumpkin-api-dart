// Brackets (pure part): `BracketBlock.getSuitableBracket` and the bracket block state. The block
// entity behaviour that stores the bracket is in `bracketed_behaviour.dart`.
import '../api/block_state.dart';
import '../common/direction.dart';

const String woodenBracketKey = 'create:wooden_bracket';
const String metalBracketKey = 'create:metal_bracket';

/// `BracketBlock.BracketType`.
enum BracketType {
  pipe,
  cog,
  shaft;

  String get serializedName => name;
}

/// What a bracket can be attached to: the axis of a straight shaft, cogwheel or pipe.
final class BracketTarget {
  /// The axis the target runs along (`null`: not suitable, for example a pipe with a bend).
  final Axis? axis;
  final BracketType type;

  const BracketTarget(this.axis, this.type);
}

/// `BracketBlock.getSuitableBracket(axis, direction, type)`: the state of the bracket block that
/// fits a target running along [targetBlockAxis] on its [direction] side, or `null`.
/// [defaultState] is the default state of the bracket block.
BState? suitableBracket(BState defaultState, Axis? targetBlockAxis, Direction direction, BracketType type) {
  final axis = direction.axis;
  if (targetBlockAxis == null || targetBlockAxis == axis) return null;
  final alongFirst = axis != Axis.z ? targetBlockAxis == Axis.z : targetBlockAxis == Axis.y;
  return defaultState
      .setValue('type', type.serializedName)
      .setValue('facing', direction.serializedName)
      .setFlag('axis_along_first', !alongFirst);
}

/// `BracketBlock.rotate`: an odd rotation cycles `axis_along_first`, then the facing rotates.
BState bracketRotate(BState state, BlockRotation rot) {
  if (rot.index % 2 == 1) state = state.cycleFlag('axis_along_first');
  final facing = state.dir('facing');
  return facing == null ? state : state.setValue('facing', rot.rotate(facing).serializedName);
}

/// `WrenchableDirectionalBlock.getRotatedBlockState`.
BState wrenchableDirectionalRotated(BState original, Direction targetedFace) {
  final facing = original.dir('facing');
  if (facing == null || facing.axis == targetedFace.axis) return original;
  return original.setValue('facing', facing.clockWiseAround(targetedFace.axis).serializedName);
}
