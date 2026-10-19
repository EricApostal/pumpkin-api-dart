// `FluidTankMovementBehavior`: a fluid tank on a contraption keeps its fluid level animated. The
// level is a client side `LerpedFloat` that has to tick while the contraption stands still, hence
// `mustTickWhileDisabled`; the server has no work to do here, but the behaviour is registered so
// the tank becomes a contraption actor like in Java.
import '../contraptions/core/movement.dart';

/// `FluidTankMovementBehavior`.
final class FluidTankMovementBehaviour extends MovementBehaviour {
  const FluidTankMovementBehaviour();

  @override
  bool mustTickWhileDisabled() => true;
}
