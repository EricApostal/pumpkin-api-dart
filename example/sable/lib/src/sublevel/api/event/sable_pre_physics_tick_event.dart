// `dev.ryanhcode.sable.api.event.SablePrePhysicsTickEvent`: fired while the
// physics system is ticking, once per physics substep.
//
// Java declares a functional interface; a Dart function type is the equivalent.
//
// Pure: no host imports.
import '../../system/physics_system.dart';

/// `prePhysicsTick(physicsSystem, timeStep)`.
typedef SablePrePhysicsTickEvent = void Function(
  SubLevelPhysicsSystem physicsSystem,
  double timeStep,
);
