// `dev.ryanhcode.sable.api.physics.object.ArbitraryPhysicsObject`: a body the
// physics system owns but that is not a sub-level (a box, a rope, a
// contraption-mounted collider).
//
// The system keeps them in a set, ticks them with the pipeline, and unloads
// them when the chunk they live in stops being loaded
// (`PhysicsChunkTicketManager.update`).
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../storage/holding/sub_level_holding_chunk_map.dart';

/// A physics object that is not a sub-level.
abstract interface class ArbitraryPhysicsObject {
  /// Writes the world-space bounds of the object into [dest]
  /// (`getBoundingBox(BoundingBox3d)`).
  void getBoundingBox(BoundingBox3d dest);

  /// Wakes the object up.
  void wakeUp();

  /// Called when the object is added to [system].
  void onAddition(SubLevelPhysicsSystemLike system) {}

  /// Called when the object is removed from the system.
  void onRemoved() {}

  /// Called when a chunk the object overlaps stopped being loaded.
  void onUnloaded(SubLevelHoldingChunkMap holdingChunkMap, (int, int) chunkPos) {}
}

/// The part of the physics system an arbitrary object sees when it is added.
///
/// Declared here rather than importing the system keeps the two files free of a
/// cycle.
abstract interface class SubLevelPhysicsSystemLike {}
