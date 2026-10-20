// The Sable block-entity hooks the plot knows about. Sable's Java code has two
// marker interfaces for block entities that take part in sub-level physics; the
// Create port has no equivalent yet, so they are declared here as the contract
// the plot and the physics tick use.
//
// HOST GAP: nothing in the Pumpkin API exposes "the block entity at this
// position" to a plugin-owned chunk outside the generated world, so
// `LevelPlot.onBlockChange` receives the resolved actor/wheel from its host
// implementation rather than looking it up itself.
//
// Pure: no host imports.

/// `dev.ryanhcode.sable.api.block.BlockEntitySubLevelActor`: a block entity
/// that is ticked once per physics tick of its sub-level.
abstract interface class BlockEntitySubLevelActor {
  /// `sable$physicsTick(ServerSubLevel, RigidBodyHandle, double)`.
  ///
  /// The handle is opaque to the model (`Object`) until the physics workstream
  /// (W3) lands its Dart pipeline.
  void sable$physicsTick(Object subLevel, Object handle, double timeStep);
}

/// `dev.ryanhcode.sable.api.block.BlockEntitySubLevelReactionWheel`: a block
/// entity that contributes reaction torque.
abstract interface class BlockEntitySubLevelReactionWheel {}
