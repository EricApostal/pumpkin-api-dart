// `BlazeBurnerMovementBehaviour`: the blaze burner as a contraption actor. The Java tick only
// animates the flame and the conductor hat on the client; the server keeps the actor so the
// contraption controls cannot disable it and so the "conductor" flag can be reset when a train
// schedule changes. Ported from `content/processing/burner/BlazeBurnerMovementBehaviour.java`.
import '../../contraptions/core/movement.dart';
import '../../contraptions/storage/stacks.dart' show StoredStack;

/// The blaze burner actor.
class BlazeBurnerMovementBehaviour extends MovementBehaviour {
  const BlazeBurnerMovementBehaviour();

  /// `canBeDisabledVia`: a blaze burner never appears in the contraption controls.
  @override
  StoredStack? canBeDisabledVia(MovementContext context) => null;

  /// `tick`: the Java implementation returns immediately on the server (particles and the head
  /// angle are client only).
  @override
  void tick(MovementContext context) {}

  /// `invalidate`: forgets the cached conductor flag of the actor.
  void invalidate(MovementContext context) => context.data.remove('Conductor');

  @override
  bool disableBlockEntityRendering() => true;
}
