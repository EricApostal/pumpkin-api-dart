// `dev.ryanhcode.sable.api.particle.ParticleSubLevelKickable`: a particle that
// decides whether sub-levels may kick/collide with it.
//
// Java's version extends a client-only `Particle`; the Dart port only carries the
// decisions, so it stays usable on the server side of the plugin.
//
// Pure: no host imports.
import '../math/oriented_bounding_box.dart';
import '../../math/vector.dart';

/// A particle that takes part in sub-level tracking.
abstract interface class ParticleSubLevelKickable {
  /// Whether this particle cares about intersecting sub-levels at all.
  bool sable$shouldCareAboutIntersectingSubLevels() => true;

  /// Whether this particle should be kicked out of the tracking sub-level.
  bool sable$shouldKickFromTracking();

  /// Whether this particle should collide with the tracking sub-level.
  bool sable$shouldCollideWithTrackingSubLevel();

  /// The particle's up direction (`+Y` by default).
  Vector3d sable$getUpDirection() => OrientedBoundingBox3d.unitY;
}
