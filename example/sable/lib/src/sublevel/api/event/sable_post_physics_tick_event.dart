// `dev.ryanhcode.sable.api.event.SablePostPhysicsTickEvent`: fired when a
// physics substep completed.
//
// Note that several physics ticks happen per game tick; logic that influences
// the physics world belongs here, not in the game tick.
//
// Pure: no host imports.
import '../../system/physics_system.dart';

/// `postPhysicsTick(physicsSystem, timeStep)`.
typedef SablePostPhysicsTickEvent = void Function(
  SubLevelPhysicsSystem physicsSystem,
  double timeStep,
);
