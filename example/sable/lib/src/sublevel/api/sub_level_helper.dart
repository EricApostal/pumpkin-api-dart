// `dev.ryanhcode.sable.api.SubLevelHelper`: the interactions between sub-levels
// and levels (entity projection, velocity, dependency chains).
//
// Java caches the entity rotations in a `ThreadLocal`; the Dart plugin is
// single-threaded, so one static holder does the same job.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../host/sub_level_host.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level.dart';
import '../model/sub_level_container.dart';
import '../math/bounding_box.dart';
import '../math/vector.dart';
import '../system/physics_system.dart';
import 'entity/sub_level_entity.dart';

/// `EntityAnchorArgument.Anchor`, the two anchors the helpers project.
enum EntityAnchor { feet, eyes }

/// A wind source: `(position, level) -> air velocity`, or `null` for none.
typedef WindProvider = Vector3d? Function(Vector3d pos, SableLevel level);

/// A helper class for sub-level <-> sub-level and sub-level <-> level
/// interactions.
abstract final class SubLevelHelper {
  static final _EntityRot _oldRot = _EntityRot();
  static final List<WindProvider> _windProviders = [];

  /// Projects [entity] into the local space of [subLevel], rotations included.
  ///
  /// Caches the old rotations; call [popEntityLocal] before pushing another
  /// entity.
  static void pushEntityLocal(SubLevel subLevel, SubLevelEntity entity, [EntityAnchor anchor = EntityAnchor.feet]) {
    if (anchor == EntityAnchor.feet) {
      entity.setPosRaw(subLevel.logicalPose.transformPositionInverse(entity.position));
    } else {
      entity.setPosRaw(
        subLevel.logicalPose
            .transformPositionInverse(entity.eyePosition)
            .sub(Vector3d(0.0, entity.eyeHeight, 0.0)),
      );
    }

    final playerLookAngle = subLevel.logicalPose.transformNormalInverse(entity.lookAngle);
    _oldRot.copy(entity);

    final pTarget = entity.eyePosition.add(playerLookAngle);
    final vec3 = entity.eyePosition;
    final d0 = pTarget.x - vec3.x;
    final d1 = pTarget.y - vec3.y;
    final d2 = pTarget.z - vec3.z;
    final d3 = math.sqrt(d0 * d0 + d2 * d2);
    entity
      ..xRot = _wrapDegrees(-(math.atan2(d1, d3) * (180.0 / math.pi)))
      ..yRot = _wrapDegrees(math.atan2(d2, d0) * (180.0 / math.pi) - 90.0)
      ..yHeadRot = _wrapDegrees(math.atan2(d2, d0) * (180.0 / math.pi) - 90.0)
      ..deltaMovement = subLevel.logicalPose.transformNormalInverse(entity.deltaMovement);
  }

  /// Projects [entity] out of [subLevel], using the rotations cached by
  /// [pushEntityLocal].
  static void popEntityLocal(SubLevel subLevel, SubLevelEntity entity, [EntityAnchor anchor = EntityAnchor.feet]) {
    if (anchor == EntityAnchor.feet) {
      entity.setPosRaw(subLevel.logicalPose.transformPosition(entity.position));
    } else {
      entity.setPosRaw(
        subLevel.logicalPose
            .transformPosition(entity.eyePosition)
            .sub(Vector3d(0.0, entity.eyeHeight, 0.0)),
      );
    }

    _oldRot.apply(entity);
    entity.deltaMovement = subLevel.logicalPose.transformNormal(entity.deltaMovement);
  }

  /// The global velocity of [pos] relative to the air, in m/s.
  static Vector3d getVelocityRelativeToAir(SableLevel level, Vector3d pos, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final probePos = Vector3d.copy(pos);
    final velocity = getVelocity(level, pos, out);

    for (final provider in _windProviders) {
      final airVelocity = provider(probePos, level);
      if (airVelocity != null) velocity.sub(airVelocity);
    }

    return velocity;
  }

  /// Registers a wind source.
  static void registerWindProvider(WindProvider function) => _windProviders.add(function);

  /// Forgets every registered wind source.
  static void clearWindProviders() => _windProviders.clear();

  /// The global velocity of [pos] in [level], taking sub-levels into account.
  static Vector3d getVelocity(SableLevel level, Vector3d pos, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final subLevel = getContainingPos(level, pos);
    if (subLevel == null) return out.zero();
    return getVelocityOfSubLevel(level, subLevel, pos, out);
  }

  /// The global velocity of [pos] on [subLevel].
  static Vector3d getVelocityOfSubLevel(
    SableLevel level,
    SubLevel subLevel,
    Vector3d pos, [
    Vector3d? dest,
  ]) {
    final out = dest ?? Vector3d();
    final pose = subLevel.logicalPose;

    if (subLevel is ServerSubLevel) {
      final container = SubLevelContainer.of(level);
      final physics = container is ServerSubLevelContainer ? container.physics : null;
      if (physics is SubLevelPhysicsSystem) {
        final handle = physics.getPhysicsHandle(subLevel);
        final linearVelocity = handle.getLinearVelocity();
        final angularVelocity = handle.getAngularVelocity();
        final localPos = pose.transformPosition(pos).sub(pose.position());
        return angularVelocity.crossInto(localPos, out).add(linearVelocity);
      }
      // No physics system attached yet: fall through to the pose delta.
    }

    // Uses the pose delta between the last and current tick, scaled to m/s.
    final transformed = pose.transformPosition(pos);
    final lastTransformed = subLevel.lastPose.transformPosition(pos);
    return transformed.subInto(lastTransformed, out).mul(20.0);
  }

  /// Projects [pos] out of any sub-level it is in.
  static Vector3d projectOutOfSubLevel(SableLevel level, Vector3d pos) {
    final subLevel = getContainingPos(level, pos);
    if (subLevel == null) return Vector3d.copy(pos);
    return subLevel.logicalPose.transformPosition(pos);
  }

  /// The sub-level containing the block position [pos].
  static SubLevel? getContaining(SableLevel level, (int, int, int) pos) =>
      getContainingAtChunk(level, pos.$1 >> 4, pos.$3 >> 4);

  /// The sub-level containing the position [pos].
  static SubLevel? getContainingPos(SableLevel level, Vector3d pos) =>
      getContaining(level, (pos.x.floor(), pos.y.floor(), pos.z.floor()));

  /// The sub-level whose plot contains the chunk.
  static SubLevel? getContainingAtChunk(SableLevel level, int chunkX, int chunkZ) {
    final container = SubLevelContainer.of(level);
    if (container == null) return null;
    return container.getPlot(chunkX, chunkZ)?.getSubLevel();
  }

  /// `ActiveSableCompanion.runIncludingSubLevels`: runs [converter] on every
  /// position [origin] can mean, and returns the first non-`null` result.
  ///
  /// The candidates, in order:
  ///
  /// 1. [origin] itself as a block position, when [shouldCheckOrigin] (the
  ///    block position is in the same space as the caller);
  /// 2. [origin] projected out of [subLevel] into the main level, with `null`
  ///    as the converter's sub-level;
  /// 3. [origin] projected into every *other* sub-level whose bounds intersect
  ///    the projected position.
  ///
  /// This is how the Create compat layer makes a lookup that Create performs in
  /// one space also see the other spaces: the caller supplies the lookup and
  /// the helper supplies the positions.
  static T? runIncludingSubLevels<T>(
    SableLevel level,
    Vector3d origin,
    bool shouldCheckOrigin,
    SubLevel? subLevel,
    T? Function(SubLevel? subLevel, (int, int, int) pos) converter,
  ) {
    final mutablePos = Vector3d.copy(origin);

    if (shouldCheckOrigin) {
      final test = converter(subLevel, _blockPosOf(mutablePos));
      if (test != null) return test;
    }

    if (subLevel != null) {
      subLevel.logicalPose.transformPosition(mutablePos, mutablePos);
      final test = converter(null, _blockPosOf(mutablePos));
      if (test != null) return test;
    }

    final copyPos = Vector3d.copy(mutablePos);
    for (final other in getAllIntersecting(level, BoundingBox3d.fromPos(_blockPosOf(mutablePos)))) {
      if (identical(other, subLevel)) continue;

      mutablePos.setFrom(copyPos);
      other.logicalPose.transformPositionInverse(mutablePos, mutablePos);
      final test = converter(other, _blockPosOf(mutablePos));
      if (test != null) return test;
    }

    return null;
  }

  /// `ActiveSableCompanion.findIncludingSubLevels`: whether any candidate
  /// position of [origin] satisfies [predicate].
  static bool findIncludingSubLevels(
    SableLevel level,
    Vector3d origin,
    bool shouldCheckOrigin,
    SubLevel? subLevel,
    bool Function(SubLevel? subLevel, (int, int, int) pos) predicate,
  ) =>
      runIncludingSubLevels<bool>(
        level,
        origin,
        shouldCheckOrigin,
        subLevel,
        (candidate, pos) => predicate(candidate, pos) ? true : null,
      ) ??
      false;

  /// `ActiveSableCompanion.distanceSquaredWithSubLevels`: the distance between
  /// [a] and [b] once both are projected out of their sub-levels.
  static double distanceSquaredWithSubLevels(SableLevel level, Vector3d a, Vector3d b) =>
      projectOutOfSubLevel(level, a).distanceSquared(projectOutOfSubLevel(level, b));

  /// `ActiveSableCompanion.distanceSquaredWithSubLevels(level, a, x, y, z)`.
  static double distanceSquaredWithSubLevelsTo(
    SableLevel level,
    Vector3d a,
    double bX,
    double bY,
    double bZ,
  ) => distanceSquaredWithSubLevels(level, a, Vector3d(bX, bY, bZ));

  static (int, int, int) _blockPosOf(Vector3d pos) => (pos.x.floor(), pos.y.floor(), pos.z.floor());

  /// All sub-levels whose global bounds intersect [bounds].
  static Iterable<SubLevel> getAllIntersecting(SableLevel level, BoundingBox3dc bounds) {
    final container = SubLevelContainer.of(level);
    if (container == null) return const [];
    return container.queryIntersecting(bounds);
  }

  /// The chain of sub-levels that should load/unload with [subLevel].
  static Set<ServerSubLevel> getLoadingDependencyChain(ServerSubLevel subLevel) {
    final visited = <ServerSubLevel>{};
    final frontier = <ServerSubLevel>{subLevel};

    while (frontier.isNotEmpty) {
      final current = frontier.first;
      frontier.remove(current);
      visited.add(current);

      final bounds = BoundingBox3d.copy(current.boundingBox);
      for (final neighbor in getAllIntersecting(current.getLevel(), bounds)) {
        if (neighbor is ServerSubLevel && !visited.contains(neighbor)) {
          frontier.add(neighbor);
        }
      }

      for (final actor in current.getPlot().getBlockEntityActors()) {
        final loadingDependencies = actor.sable$getLoadingDependencies();
        if (loadingDependencies == null) continue;
        for (final dependency in loadingDependencies) {
          if (dependency is ServerSubLevel && !visited.contains(dependency)) {
            frontier.add(dependency);
          }
        }
      }
    }

    return visited;
  }

  /// The chain of sub-levels considered connected to [subLevel].
  static Set<SubLevel> getConnectedChain(SubLevel subLevel) {
    final visited = <SubLevel>{};
    final frontier = <SubLevel>{subLevel};

    while (frontier.isNotEmpty) {
      final current = frontier.first;
      frontier.remove(current);
      visited.add(current);

      for (final actor in current.getPlot().getBlockEntityActors()) {
        final dependencies = actor.sable$getConnectionDependencies();
        if (dependencies == null) continue;
        for (final dependency in dependencies) {
          if (!visited.contains(dependency)) frontier.add(dependency);
        }
      }
    }

    return visited;
  }

  /// `Mth.wrapDegrees`.
  static double _wrapDegrees(double degrees) {
    var value = degrees % 360.0;
    if (value >= 180.0) value -= 360.0;
    if (value < -180.0) value += 360.0;
    return value;
  }
}

final class _EntityRot {
  double xRot = 0.0;
  double yRot = 0.0;
  double yHeadRot = 0.0;

  void apply(SubLevelEntity entity) {
    entity
      ..xRot = xRot
      ..yRot = yRot
      ..yHeadRot = yHeadRot;
  }

  void copy(SubLevelEntity entity) {
    xRot = entity.xRot;
    yRot = entity.yRot;
    yHeadRot = entity.yHeadRot;
  }
}
