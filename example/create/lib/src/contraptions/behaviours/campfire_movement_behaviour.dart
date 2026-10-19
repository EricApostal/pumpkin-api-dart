// `CampfireMovementBehaviour`: the campfire only emits smoke particles while it moves. That is a
// client effect, so the server side has nothing to do; the behaviour is registered so a contraption
// client looks the actor up like it does for every other block.
import '../core/movement.dart';

/// `CampfireMovementBehaviour`.
final class CampfireMovementBehaviour extends MovementBehaviour {
  const CampfireMovementBehaviour();
}
