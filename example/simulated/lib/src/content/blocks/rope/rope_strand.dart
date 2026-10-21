// A rope strand's server state, minus the physics engine.
//
// `ServerRopeStrand` extends `RopePhysicsObject`, so the points, the extension
// goal and the "do the clients need this frame?" decision are pure; the physics
// handle, the constraints and the chunk tickets are not, and stay behind
// `TODO(parity)`.
//
// Two numbers matter and are easy to mis-transcribe:
//
//  * the sync threshold is `Mth.square(1.0 / 16.0 * 0.1)` = 3.90625e-5, i.e. a
//    point must move ~6.25 mm before the strand is re-sent;
//  * `SEGMENT_LENGTH` is 1.0 and the first segment's extension goal is lerped
//    between the previous and the current goal by the partial physics tick.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.rope.strand.server
//         .ServerRopeStrand
//       dev.ryanhcode.sable.api.physics.object.rope.RopePhysicsObject
// TODO(parity): `reattachConstraints` (the two sub-levels are pinned with a free
// constraint and motors on every axis), `applyAttachment` (needs the rope
// holder block entity) and the chunk-ticket checks need Sable's pipeline.
import 'dart:math' as math;

import 'package:sable/sable.dart' show Vector3d;

/// The attachment ends of a strand.
enum RopeAttachmentPoint { start, end }

/// `RopeAttachment`: one end of a strand, and the block it is tied to.
final class RopeAttachment {
  final RopeAttachmentPoint point;

  /// The sub-level the attached block is in, or `null` for the world.
  final String? subLevelId;

  /// The block the rope is tied to.
  final (int, int, int) blockAttachment;

  const RopeAttachment(this.point, this.blockAttachment, [this.subLevelId]);

  @override
  bool operator ==(Object other) =>
      other is RopeAttachment &&
      other.point == point &&
      other.subLevelId == subLevelId &&
      other.blockAttachment == blockAttachment;

  @override
  int get hashCode => Object.hash(point, subLevelId, blockAttachment);
}

/// `ServerRopeStrand`, without the pipeline.
final class ServerRopeStrand {
  /// `ServerRopeStrand.SEGMENT_LENGTH`.
  static const double segmentLength = 1.0;

  /// `RopePhysicsObject(points, 0.125)`.
  static const double collisionRadius = 0.125;

  /// `Mth.square(1.0 / 16.0 * 0.1)`: the squared distance a point must move for
  /// the strand to be re-sent.
  static const double syncThreshold = 0.00625 * 0.00625;

  /// The strand's uuid.
  final String uuid;

  final List<Vector3d> _points;

  /// The points last sent to clients.
  final List<Vector3d> _lastNetworkedPoints = <Vector3d>[];

  final Map<RopeAttachmentPoint, RopeAttachment> _attachments = <RopeAttachmentPoint, RopeAttachment>{};

  /// The extension goal of the last game tick.
  double lastExtensionGoal = segmentLength;

  /// The current extension goal of the first segment.
  double extensionGoal = segmentLength;

  double lastFirstSegmentExtension = segmentLength;

  /// `networkingStopped`: the clients have been told the strand is at rest.
  bool networkingStopped = false;

  ServerRopeStrand(this.uuid, Iterable<Vector3d> points)
    : _points = [for (final p in points) Vector3d.copy(p)];

  /// A read-only view of the points.
  List<Vector3d> get points => List<Vector3d>.unmodifiable(_points);

  /// The attachments by end.
  Map<RopeAttachmentPoint, RopeAttachment> get attachments =>
      Map<RopeAttachmentPoint, RopeAttachment>.unmodifiable(_attachments);

  /// `getAttachment(point)`.
  RopeAttachment? attachment(RopeAttachmentPoint point) => _attachments[point];

  /// `addAttachment(point, attachment)`.
  void addAttachment(RopeAttachment attachment) => _attachments[attachment.point] = attachment;

  /// `needsSync()`: the point count changed, or a point moved further than the
  /// threshold since the last frame.
  bool needsSync() {
    if (_lastNetworkedPoints.length != _points.length) return true;
    for (var i = 0; i < _points.length; i++) {
      if (_distanceSquared(_points[i], _lastNetworkedPoints[i]) > syncThreshold) return true;
    }
    return false;
  }

  /// `justSynced()`: remembers the points that were just sent.
  void justSynced() {
    _lastNetworkedPoints
      ..clear()
      ..addAll([for (final p in _points) Vector3d.copy(p)]);
  }

  /// `updateFirstSegmentExtension(goal)`: remembers the previous goal so the
  /// physics tick can lerp between them.
  void updateFirstSegmentExtension(double goal) {
    lastExtensionGoal = extensionGoal;
    extensionGoal = goal;
  }

  /// The extension to apply this tick: `Mth.lerp(partialTick, last, current)`.
  double interpolatedExtension(double partialPhysicsTick) =>
      lastExtensionGoal + (extensionGoal - lastExtensionGoal) * partialPhysicsTick;

  /// `getCurrentExtension()`: the summed length of the segments.
  double get currentExtension {
    var total = 0.0;
    for (var i = 0; i < _points.length - 1; i++) {
      total += math.sqrt(_distanceSquared(_points[i], _points[i + 1]));
    }
    return total;
  }

  /// `addPoint(position)`: the point goes to the *front* of the strand.
  void addPoint(Vector3d position) => _points.insert(0, Vector3d.copy(position));

  /// `removeFirstPoint()`.
  void removeFirstPoint() {
    if (_points.isNotEmpty) _points.removeAt(0);
  }

  /// `prePhysicsTick`: the extension of the first segment only changes when it
  /// actually differs from the applied one.
  ///
  /// Returns whether the caller has to call `setFirstSegmentLength`.
  bool prepareFirstSegment(double partialPhysicsTick) {
    final extension = interpolatedExtension(partialPhysicsTick);
    if (extension == lastFirstSegmentExtension) return false;
    lastFirstSegmentExtension = extension;
    return true;
  }

  static double _distanceSquared(Vector3d a, Vector3d b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
  }
}
