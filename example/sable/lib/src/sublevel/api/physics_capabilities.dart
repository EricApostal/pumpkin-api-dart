// The capability seam of the physics pipeline: which parts of the
// `PhysicsPipeline` contract an engine can actually implement.
//
// `PhysicsPipeline.java:76,92` makes contraptions and ropes entry points of
// every engine, and the Java engines all accept them (`RapierPhysicsPipeline`
// builds a kinematic body; `StaticPhysicsPipeline.java:65-90` ignores them).
// An engine that cannot implement one of them has no honest implementation for
// it, so it declares the feature unsupported here instead of throwing from a
// call Sable makes unconditionally. Sable's call sites
// (`compat/create/contraption_physics.dart`, `command/sable_spawn_commands.dart`)
// consult [PhysicsPipelineCapabilities.supportsFeature] before calling, and an
// engine that is asked anyway throws [UnsupportedPhysicsFeatureException].
//
// This mirrors `RopeAttachable` (`physics_rope.dart`): a pipeline capability
// only some engines have gets its own interface instead of a member every
// implementation must fake.
//
// Pure: no host imports.
import 'physics_pipeline.dart';

/// A part of the [PhysicsPipeline] contract an engine may not implement.
enum PhysicsPipelineFeature {
  /// Kinematic contraption bodies: `addContraption`/`removeContraption`
  /// (`RapierPhysicsPipeline.java:225-299`, `createKinematicContraption`).
  contraption,

  /// Rope chains: `addRope`/`removeRope`
  /// (`sable_rapier/src/main/rust/rapier/src/rope.rs:108-260`).
  rope,
}

/// A pipeline that declares which [PhysicsPipelineFeature]s it implements.
///
/// A pipeline that does **not** implement this interface is taken to support
/// every feature (the Java contract, where every engine accepts the calls).
/// That keeps pipelines which predate the seam — the `impl/none` fallback and
/// every test fake — working unchanged.
abstract interface class FeatureAwarePhysicsPipeline {
  /// Whether this pipeline's entry points for [feature] can be used.
  ///
  /// `false` means the entry points are not implemented and throw an
  /// [UnsupportedPhysicsFeatureException]; callers must check this instead of
  /// calling them.
  bool supportsFeature(PhysicsPipelineFeature feature);
}

/// [FeatureAwarePhysicsPipeline.supportsFeature] for any pipeline.
extension PhysicsPipelineCapabilities on PhysicsPipeline {
  /// Whether this pipeline implements [feature].
  bool supportsFeature(PhysicsPipelineFeature feature) =>
      this is FeatureAwarePhysicsPipeline
          ? (this as FeatureAwarePhysicsPipeline).supportsFeature(feature)
          : true;
}

/// Thrown when a [PhysicsPipelineFeature] is used on a pipeline that does not
/// implement it.
///
/// Unlike a bare `UnimplementedError`, this names both the feature and what the
/// engine is missing, so a caller can report a precise reason (and the guard in
/// [PhysicsPipelineCapabilities] keeps it unreachable in normal operation).
class UnsupportedPhysicsFeatureException implements Exception {
  /// The feature that was used.
  final PhysicsPipelineFeature feature;

  /// What the engine is missing to implement [feature].
  final String missingCapability;

  UnsupportedPhysicsFeatureException(this.feature, this.missingCapability);

  @override
  String toString() =>
      'UnsupportedPhysicsFeatureException: this physics pipeline does not '
      'implement ${feature.name}; it is missing $missingCapability. Callers '
      'must check `supportsFeature(${feature.name})` first.';
}