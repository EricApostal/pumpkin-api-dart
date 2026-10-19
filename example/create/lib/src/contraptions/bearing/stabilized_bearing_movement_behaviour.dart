// `StabilizedBearingMovementBehaviour`: the actor of a mechanical bearing that is carried by
// another contraption. The bearing itself keeps its blocks in place (its sub-contraption is
// stabilized by `BearingContraption.canBeStabilized`), so this actor never acts on the world.
//
// Java: `content/contraptions/bearing/StabilizedBearingMovementBehaviour`. The rendering methods
// (`renderInContraption`, `createVisual`, `getCounterRotationAngle`) only draw the bearing top and
// are not ported; the server-relevant part is that the actor cannot be disabled by contraption
// controls and that the carried block entity is not rendered.
import '../core/movement.dart';
import '../storage/stacks.dart';

final class StabilizedBearingMovementBehaviour extends MovementBehaviour {
  const StabilizedBearingMovementBehaviour();

  /// `canBeDisabledVia`: a bearing on a contraption is never switched off by the controls.
  @override
  StoredStack? canBeDisabledVia(MovementContext context) => null;

  /// `disableBlockEntityRendering`: the bearing top is drawn by the actor, not the block entity.
  @override
  bool disableBlockEntityRendering() => true;
}
