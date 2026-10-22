// `dev.ryanhcode.sable.sublevel.storage.serialization.SubLevelSerializer`:
// serializes and saves sub-levels.
//
// The tag layout matches the Java mod:
// `uuid`, `plot`, `pose`, `world_bounds`, optional `linear_velocity`,
// `angular_velocity`, `display_name`, `loading_dependencies`, `user_data`.
//
// `fullyLoad` needs the physics pipeline to teleport the body and to restore
// velocity; that part is marked `DEPENDS ON W3`.
//
// Pure: no host imports (all host work goes through the container/host).
import '../../math/bounding_box.dart';
import '../../math/pose.dart';
import '../../math/vector.dart';
import '../../model/mass_tracker.dart';
import '../../model/server_sub_level.dart';
import '../../model/sub_level_container.dart';
import '../../util/sable_nbt.dart';
import '../sub_level_removal_reason.dart';
import 'sub_level_data.dart';

/// Serializes and saves sub-levels to disk.
abstract final class SubLevelSerializer {
  /// For when absolutely everything is broken and the state management has to
  /// be stepped through (kept from the Java mod; it only gates logging there).
  static const bool superDebugMode = false;

  /// Serializes [subLevel] to its NBT-shaped tag.
  static Map<String, Object?> serialize(ServerSubLevel subLevel, List<String> dependencies) {
    final tag = <String, Object?>{};
    final plot = subLevel.getPlot();

    SableNbt.putUuid(tag, 'uuid', subLevel.uniqueId);
    tag['plot'] = plot.save();

    // The serialized pose is recentred on the centre of mass so the physics body
    // is reconstructed around the same point.
    final serializedPose = Pose3d.copy(subLevel.logicalPose);
    final centerOfMass = _selfCenterOfMassOrOrigin(subLevel);
    serializedPose.position().setFrom(subLevel.logicalPose.transformPosition(Vector3d.copy(centerOfMass)));
    serializedPose.rotationPoint().setFrom(centerOfMass);

    tag['pose'] = SableNbt.writePose3d(serializedPose);
    tag['world_bounds'] = SableNbt.writeBoundingBox(subLevel.boundingBox);

    final velocity = subLevel.physicsBody;
    if (velocity != null) {
      final linear = velocity.getLinearVelocity();
      final angular = velocity.getAngularVelocity();

      if (linear.lengthSquared > 0.1 * 0.1) {
        tag['linear_velocity'] = SableNbt.writeVector3d(linear);
      }
      // Java compares against `Math.toRadians(1.0)` (which is a *squared*
      // length there too, a known quirk kept for compatibility).
      if (angular.lengthSquared > 0.017453292519943295) {
        tag['angular_velocity'] = SableNbt.writeVector3d(angular);
      }
    }

    final name = subLevel.name;
    if (name != null) tag['display_name'] = name;

    if (dependencies.isNotEmpty) {
      tag['loading_dependencies'] = [
        for (final dependency in dependencies) SableNbt.writeUuid(dependency),
      ];
    }

    final userData = subLevel.getUserDataTag();
    if (userData != null) tag['user_data'] = userData;

    return tag;
  }

  /// Reads a half-loaded sub-level from [tag], or `null` when it is malformed.
  static SubLevelData? fromData(Map<String, Object?> tag) {
    final uuid = SableNbt.getUuid(tag, 'uuid');
    if (uuid == null) return null;

    var dependencies = <String>[];
    final dependencyTags = tag['loading_dependencies'];
    if (dependencyTags is List) {
      dependencies = [
        for (final dependency in dependencyTags)
          if (dependency is List)
            SableNbt.readUuid(dependency),
      ];
    }

    final pose = SableNbt.readPose3d(tag['pose']);
    final worldBounds = SableNbt.readBoundingBox(tag['world_bounds']);

    return SubLevelData(uuid, worldBounds, pose, dependencies, tag);
  }

  /// Fully loads a sub-level and adds it to its container.
  ///
  /// Returns `null` when the tag is unusable (invalid pose, occupied plot, empty
  /// bounds), like the Java method — and reports *why* through [onFailure], which
  /// the Java method logs at error level. A `null` without a reason is a
  /// sub-level that silently disappears.
  static ServerSubLevel? fullyLoad(
    SubLevelContainer container,
    SubLevelData halfLoadedSubLevel, {
    void Function(String message, Object? error)? onFailure,
  }) {
    final tag = halfLoadedSubLevel.fullTag;
    final plotTag = tag['plot'];
    final plotMap = plotTag is Map ? Map<String, Object?>.from(plotTag) : const <String, Object?>{};

    final plotX = (plotMap['plot_x'] as num?)?.toInt() ?? 0;
    final plotZ = (plotMap['plot_z'] as num?)?.toInt() ?? 0;

    final pose = SableNbt.readPose3d(tag['pose']);
    final position = pose.position();
    final rotationPoint = pose.rotationPoint();

    if (!position.isFinite || !rotationPoint.isFinite) {
      onFailure?.call('Failed to load sub-level ${halfLoadedSubLevel.uuid}, invalid pose', null);
      return null;
    }

    final ServerSubLevel subLevel;
    try {
      final allocated = container.allocateSubLevel(halfLoadedSubLevel.uuid, plotX, plotZ, pose);
      if (allocated is! ServerSubLevel) {
        onFailure?.call(
          'Failed to load sub-level ${halfLoadedSubLevel.uuid}: the container allocated a '
          'non-server sub-level at plot ($plotX, $plotZ)',
          null,
        );
        return null;
      }
      subLevel = allocated;
    } on ArgumentError catch (error) {
      onFailure?.call(
        'Failed to load sub-level ${halfLoadedSubLevel.uuid} at plot ($plotX, $plotZ), skipping',
        error,
      );
      return null;
    }

    final plot = subLevel.getPlot();
    plot.load(plotMap);

    // `allocateSubLevel` fires `onSubLevelAdded`, which builds the mass tracker —
    // but the plot was still empty at that point, so the tracker describes no
    // blocks and reads as invalid. The next tick's removal pass then destroys
    // the plot and removes the sub-level, silently: the ship was on disk, came
    // back for one tick, and vanished. Java never sees this because its
    // `MassTracker` is rebuilt by `SubLevelPhysicsSystem.recoverSubLevel` on the
    // paths that matter; the port rebuilds it here, once the blocks exist.
    subLevel.buildMassTracker();
    // `buildMassTracker` wraps a fresh `MergedMassTracker`, whose own `mass` and
    // `centerOfMass` stay empty until `update` runs — and the container's
    // removal pass runs *before* the physics substeps of the same tick, so an
    // un-primed merged tracker still reads as invalid and the sub-level is
    // removed anyway. Priming it here is what makes the restore survive its
    // first tick.
    subLevel.updateMergedMassData(0.0);

    final bounds = plot.getBoundingBox();
    if (identical(bounds, BoundingBox3i.empty) || bounds.volume() <= 0) {
      onFailure?.call(
        'Failed to load sub-level ${halfLoadedSubLevel.uuid}, invalid plot bounds: '
        '${identical(bounds, BoundingBox3i.empty) ? 'EMPTY' : bounds} '
        '(${plot.getLoadedChunks().length} chunk(s) restored)',
        null,
      );
      container.removeSubLevelAt(subLevel, SubLevelRemovalReason.removed);
      return null;
    }

    subLevel.logicalPose.position().setFrom(position);
    subLevel.logicalPose.orientation().setFrom(pose.orientation());

    // DEPENDS ON W3: the physics pipeline teleports the body and restores the
    // velocity here (`PhysicsPipeline.teleport` / `addLinearAndAngularVelocity`).
    // Without a body the pose is authoritative, so the model is already correct;
    // the velocity is left to the physics system.
    final body = subLevel.physicsBody;
    final retention = container.velocityRetainedOnLoad;
    if (body != null) {
      body.teleport(position, pose.orientation());
      final linearTag = tag['linear_velocity'];
      final angularTag = tag['angular_velocity'];
      final linear = linearTag == null ? Vector3d() : SableNbt.readVector3d(linearTag).mul(retention);
      final angular = angularTag == null ? Vector3d() : SableNbt.readVector3d(angularTag).mul(retention);
      body.addLinearAndAngularVelocity(linear, angular);
    }

    subLevel.updateLastPose();

    final name = tag['display_name'];
    if (name is String) subLevel.setName(name);

    final userData = tag['user_data'];
    if (userData is Map) subLevel.setUserDataTag(Map<String, Object?>.from(userData));

    subLevel.updateBoundingBox();
    subLevel.forceUpdateGlobalBounds();
    return subLevel;
  }

  /// Serializes [subLevel] into a [SubLevelData], dropping [subLevel] itself
  /// from its dependency list.
  static SubLevelData toData(ServerSubLevel subLevel, List<String> dependencies) {
    final filtered = [
      for (final dependency in dependencies)
        if (dependency != subLevel.uniqueId) dependency,
    ];
    final tag = serialize(subLevel, filtered);

    return SubLevelData(
      subLevel.uniqueId,
      BoundingBox3d.copy(subLevel.boundingBox),
      Pose3d.copy(subLevel.logicalPose),
      filtered,
      tag,
    );
  }

  /// The centre of mass the saved pose is recentred on, or the origin when the
  /// sub-level has none.
  ///
  /// Java recentres on the **self** tracker (`SubLevelSerializer.java:50-53`:
  /// `getSelfMassTracker().getCenterOfMass()`), not the merged one: the saved
  /// pose is the sub-level's own body frame, and a kinematic contraption riding
  /// on it must not move the reconstruction point.
  static Vector3d _selfCenterOfMassOrOrigin(ServerSubLevel subLevel) {
    // `getSelfMassTracker()` throws when the physics system has not built one
    // yet (a sub-level serialized straight after allocation) and when the
    // installed tracker is a plain `MassData` (the test fakes); Java's serializer
    // can assume a `MassTracker` because its physics system always builds one.
    final tracker = subLevel.massTracker;
    if (tracker == null) return Vector3d();
    final self = tracker is MergedMassTracker ? tracker.selfTracker : tracker;
    return self.isInvalid() ? Vector3d() : Vector3d.copy(self.getCenterOfMass());
  }
}
