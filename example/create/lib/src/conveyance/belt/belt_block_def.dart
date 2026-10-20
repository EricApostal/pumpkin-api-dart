// The `IRotate` rules of `create:belt` (`BeltBlock.getRotationAxis`,
// `BeltBlock.hasShaftTowards` and `areStatesKineticallyEquivalent`). Kept out of
// `belt_block_entity.dart`, which imports the host, so the unit tests can run
// the rules on the plain Dart VM.
import '../../kinetics/block_defs.dart' show KineticBlockDef;
import '../../kinetics/geometry.dart' show Dir, KAxis, KState;
import 'belt_geometry.dart' show BeltPart, BeltSlope;

/// The `IRotate` rules of the belt: the rotation axis follows the facing, and
/// only the parts with a pulley (start, end, pulley) have a shaft.
class BeltBlockDef extends KineticBlockDef {
  const BeltBlockDef();

  /// `BeltBlock.getRotationAxis`: the axis perpendicular to the belt, or `y` for
  /// a sideways belt.
  @override
  KAxis rotationAxis(KState state) {
    if (state['slope'] == BeltSlope.sideways.name) return KAxis.y;
    final facing = state.dirOf('facing') ?? Dir.north;
    return facing.clockWise(KAxis.y).axis;
  }

  /// `BeltBlock.hasShaftTowards`: only on the rotation axis, and only where the
  /// block entity reports a pulley. `BeltBlockEntity.hasPulley()` is exactly
  /// "the part is not `middle`", so the state alone decides it.
  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state) &&
      (state['part'] ?? BeltPart.start.name) != BeltPart.middle.name;

  /// `BeltBlock.areStatesKineticallyEquivalent`: the part matters too (a pulley
  /// has a shaft, a middle segment does not).
  @override
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) {
    if (oldState.block != newState.block) return false;
    if (oldState['part'] != newState['part']) return false;
    return rotationAxis(newState) == rotationAxis(oldState);
  }
}
