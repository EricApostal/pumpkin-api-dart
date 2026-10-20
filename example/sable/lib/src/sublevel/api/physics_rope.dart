// `dev.ryanhcode.sable.api.physics.object.rope`: the rope attachment seam.
//
// `RopePhysicsObject`/`RopeHandle` live in `api/physics_pipeline.dart` (the
// physics workstream); anchoring a rope end to the world or to a sub-level is
// an extra pipeline capability, so it gets its own interface and the commands
// report a precise failure when the pipeline does not implement it.
//
// Pure: no host imports.
import '../math/vector.dart';
import 'physics_pipeline.dart';

/// The attachment end of a rope (`RopeHandle.AttachmentPoint`).
enum RopeAttachmentPoint { start, end }

/// A pipeline that can anchor rope ends.
abstract interface class RopeAttachable {
  /// `setAttachment(point, position, subLevel)`: [subLevel] is `null` for the
  /// world.
  void setAttachment(
    RopeHandle rope,
    RopeAttachmentPoint point,
    Vector3d position, [
    Object? subLevel,
  ]);

  /// `addRopePointAtStart(rope)`.
  void addRopePointAtStart(RopeHandle rope);

  /// `removeRopePointAtStart(rope)`.
  void removeRopePointAtStart(RopeHandle rope);
}
