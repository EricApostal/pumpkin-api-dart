// `dev.ryanhcode.sable.physics.floating_block`: clusters the blocks of a
// sub-level by their floating material and turns them into lift and friction.
//
// The model (from the Java controller):
//
// * blocks are grouped into one [FloatingClusterContainer] per body — the
//   sub-level itself, plus one per kinematic contraption on it,
// * each container groups its blocks into one [FloatingBlockCluster] per
//   material, each with its own [FloatingBlockData],
// * per physics tick the controller folds the clusters' drag into
//   `linearImpulse` / `angularImpulse`, and applies lift through the
//   `sable:levitation` force group,
// * lift that would exceed the body's own weight is clamped by the
//   `scaleFactor` in `applyLift` so a balloon cannot accelerate forever.
//
// The inertia the friction model needs is a 3x3 tensor, which the mass tracker
// owns; [FloatingBlockBody] is the narrow view of it this file needs, and
// [FloatingBlockBody.ofSubLevel] adapts a sub-level through the hooks the
// physics workstream installs.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../api/physics.dart';
import '../math/matrix3.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import 'floating_block_data.dart';
import 'floating_block_material.dart';
import 'physics_block_properties.dart';

/// The inertia view of a body the floating-block friction model needs.
abstract interface class FloatingBlockBody {
  /// The centre of mass, in the body's local space.
  Vector3d get centerOfMass;

  /// The mass, in kilograms.
  double get mass;

  /// The inverse inertia tensor, in the body's local space.
  Matrix3d get inverseInertiaTensor;

  /// Resolves the floating material of a block state, or `null`.
  FloatingBlockMaterial? materialOf(String state);

  /// The floating scale of a block state.
  double floatingScaleOf(String state);

  /// The air pressure at a world position.
  double pressureAt(Vector3d worldPosition);
}

/// `FloatingBlockCluster`: one material's blocks inside one container.
final class FloatingBlockCluster {
  final FloatingBlockMaterial material;
  final FloatingBlockData blockData = FloatingBlockData();

  FloatingBlockCluster(this.material);

  FloatingBlockMaterial getMaterial() => material;

  FloatingBlockData getBlockData() => blockData;

  @override
  String toString() => 'FloatingBlockCluster[$material, ${blockData.blockCount} blocks]';
}

/// `FloatingClusterContainer`: the clusters of one body.
final class FloatingClusterContainer {
  /// The clusters, one per material.
  final List<FloatingBlockCluster> clusters = [];

  /// Queued additions, by block position, with the block state string.
  final Map<(int, int, int), String> addedBlocks = {};

  /// Queued removals, by block position, with the block state string.
  final Map<(int, int, int), String> removedBlocks = {};

  /// The container's offset from the body's centre of mass.
  final Vector3d positionOffset = Vector3d();

  /// The container's rotation relative to the body.
  final Quaterniond rotationOffset = Quaterniond();

  /// The container's velocity relative to the body.
  final Vector3d velocity = Vector3d();

  /// The container's angular velocity relative to the body.
  final Vector3d angularVelocity = Vector3d();

  final FloatingBlockBody _body;

  FloatingClusterContainer(this._body);

  /// `needsTicking()`.
  bool needsTicking() => addedBlocks.isNotEmpty || clusters.isNotEmpty;

  /// `processBlockChanges(centerOfMass)`.
  void processBlockChanges(Vector3d centerOfMass) {
    for (final entry in removedBlocks.entries) {
      final pos = Vector3d(
        entry.key.$1 + 0.5 - centerOfMass.x,
        entry.key.$2 + 0.5 - centerOfMass.y,
        entry.key.$3 + 0.5 - centerOfMass.z,
      );
      removeFloatingBlock(entry.value, pos);
    }

    for (final entry in addedBlocks.entries) {
      final pos = Vector3d(
        entry.key.$1 + 0.5 - centerOfMass.x,
        entry.key.$2 + 0.5 - centerOfMass.y,
        entry.key.$3 + 0.5 - centerOfMass.z,
      );
      addFloatingBlock(entry.value, pos);
    }

    addedBlocks.clear();
    removedBlocks.clear();
  }

  /// `addFloatingBlock(state, pos)`: adds to the cluster of the block's
  /// material, creating it if needed.
  void addFloatingBlock(String state, Vector3d pos) {
    final material = _body.materialOf(state);
    if (material == null) return;
    final scale = _body.floatingScaleOf(state);

    FloatingBlockCluster? found;
    for (final cluster in clusters) {
      if (cluster.material == material) {
        found = cluster;
        break;
      }
    }
    found ??= (() {
      final cluster = FloatingBlockCluster(material);
      clusters.add(cluster);
      return cluster;
    })();

    found.blockData.addFloatingBlock(pos, scale);
  }

  /// `removeFloatingBlock(state, pos)`: drops the block from its cluster and
  /// removes an empty cluster.
  void removeFloatingBlock(String state, Vector3d pos) {
    final material = _body.materialOf(state);
    if (material == null) return;
    final scale = _body.floatingScaleOf(state);

    for (final cluster in clusters.toList(growable: false)) {
      if (cluster.material != material) continue;
      cluster.blockData.removeFloatingBlock(pos, scale);
      if (cluster.blockData.blockCount <= 0) clusters.remove(cluster);
      return;
    }
  }

  /// `queueAddFloatingBlock(state, pos)`.
  void queueAddFloatingBlock(String state, (int, int, int) pos) => addedBlocks[pos] = state;

  /// `queueRemoveFloatingBlock(state, pos)`.
  void queueRemoveFloatingBlock(String state, (int, int, int) pos) => removedBlocks[pos] = state;

  /// The number of blocks in every cluster.
  int get blockCount => clusters.fold(0, (sum, cluster) => sum + cluster.blockData.blockCount);

  @override
  String toString() => 'FloatingClusterContainer[${clusters.length} clusters, $blockCount blocks]';
}

/// `FloatingBlockController`: the per-sub-level driver.
final class FloatingBlockController {
  final FloatingBlockBody _body;
  final FloatingClusterContainer sublevelContainer;
  final List<FloatingClusterContainer> containers = [];
  final Vector3d _previousCenterOfMass = Vector3d();

  final Vector3d _frictionForce = Vector3d();
  final Vector3d _frictionTorque = Vector3d();
  final Vector3d _clusterFrictionForce = Vector3d();
  final Vector3d _clusterFrictionTorque = Vector3d();
  final Vector3d _localGravity = Vector3d();
  final Vector3d _localLinearVelocity = Vector3d();
  final Vector3d _localAngularVelocity = Vector3d();
  final Vector3d _totalWeightedForce = Vector3d();
  final Vector3d _averageForcePos = Vector3d();
  final Vector3d _liftingForce = Vector3d();
  final Vector3d _liftingTorque = Vector3d();
  final Vector3d _torqueTemp = Vector3d();
  final Vector3d _weightedPositionTemp = Vector3d();
  final Vector3d _totalAcceleration = Vector3d();

  final Matrix3d _containerRotation = Matrix3d();
  final Vector3d _clusterCenter = Vector3d();
  final Vector3d _totalAngularVelocity = Vector3d();
  final Vector3d _rotatedPos = Vector3d();
  final Matrix3d _slowDragMatrix = Matrix3d();
  final Matrix3d _fastDragMatrix = Matrix3d();
  final Matrix3d _averagePositionMatrix = Matrix3d();
  final Matrix3d _averagePositionMatrixInverse = Matrix3d();
  final Matrix3d _shiftedPositionMatrix = Matrix3d();
  final Matrix3d _shiftedPositionMatrixInverse = Matrix3d();
  final Matrix3d _tempTorqueMatrix = Matrix3d();
  final Vector3d _meanVelocity = Vector3d();
  final Vector3d _shiftedCenter = Vector3d();
  final Vector3d _linearSlowDrag = Vector3d();
  final Matrix3d _x2 = Matrix3d();
  final Matrix3d _y2 = Matrix3d();
  final Matrix3d _yx = Matrix3d();
  final Matrix3d _traceMatrix = Matrix3d();

  /// The force group recorded lift goes to (`ForceGroups.LEVITATION`).
  final ForceGroup levitationGroup;

  /// The force group recorded drag goes to (`ForceGroups.DRAG`).
  final ForceGroup dragGroup;

  /// The sub-level this controller drives; `null` for a bare body.
  final ServerSubLevel? subLevel;

  FloatingBlockController(
    this._body, {
    this.subLevel,
    ForceGroup? levitationGroup,
    ForceGroup? dragGroup,
  }) : levitationGroup = levitationGroup ?? ForceGroup.levitation,
       dragGroup = dragGroup ?? ForceGroup.drag,
       sublevelContainer = FloatingClusterContainer(_body);

  /// `physicsTick(partialPhysicsTick, timeStep, linearVelocity,
  /// angularVelocity, linearImpulse, angularImpulse)`.
  ///
  /// Adds the clusters' friction and lift to [linearImpulse] and
  /// [angularImpulse]. [gravity] is the world-space gravity of the level.
  void physicsTick(
    double partialPhysicsTick,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, {
    required Vector3d gravity,
    List<FloatingClusterContainer> contraptionContainers = const [],
  }) {
    containers
      ..clear()
      ..add(sublevelContainer)
      ..addAll(contraptionContainers);

    _localGravity.setFrom(gravity);
    _bodyOrientation.transformInverse(_localGravity, _localGravity);

    processBlockChanges();

    if (!needsTicking()) return;

    _bodyOrientation.transformInverse(linearVelocity, _localLinearVelocity);
    _bodyOrientation.transformInverse(angularVelocity, _localAngularVelocity);

    _frictionForce.zero();
    _frictionTorque.zero();

    final recordedFrictionForces = <Vector3d>[];

    for (final container in containers) {
      for (final cluster in container.clusters) {
        if (cluster.material.scaleWithPressure) {
          cluster.blockData.computePressureScale(
            _subLevelOrThrow(),
            (worldPosition) => _body.pressureAt(worldPosition),
          );
        }

        applyFriction(
          container,
          cluster,
          _localGravity,
          _localLinearVelocity,
          _localAngularVelocity,
          _clusterFrictionForce,
          _clusterFrictionTorque,
        );

        final recorded = Vector3d(
          _clusterFrictionForce.x,
          _clusterFrictionForce.y,
          _clusterFrictionForce.z,
        );
        // Recording is diagnostic: only a sub-level that tracks individual
        // queued forces consumes the values, and only it has force groups.
        if (_tracksIndividualForces) {
          _recordForce(container, cluster, _queuedGroup(dragGroup), recorded);
        }
        recordedFrictionForces.add(recorded);

        _frictionForce.add(_clusterFrictionForce);
        _frictionTorque.add(_clusterFrictionTorque);
      }
    }

    for (final force in recordedFrictionForces) {
      force.mul(timeStep);
    }
    if (_localGravity.lengthSquared > 0) {
      applyLift(_localGravity, linearImpulse, angularImpulse, timeStep);
    }

    linearImpulse.fma(timeStep, _frictionForce);
    angularImpulse.fma(timeStep, _frictionTorque);
  }

  /// Whether any cluster needs ticking.
  bool needsTicking() {
    if (sublevelContainer.needsTicking()) return true;
    for (final container in containers) {
      if (container.needsTicking()) return true;
    }
    return false;
  }

  /// `processBlockChanges()`: moves the cluster origins with the centre of
  /// mass, then applies queued block changes.
  void processBlockChanges() {
    final centerOfMass = _body.centerOfMass;
    // The clusters' origins move by (old centre of mass − new centre of mass),
    // so their stored positions stay relative to the body.
    final nudge = _previousCenterOfMass.subInto(centerOfMass, Vector3d());

    for (final cluster in sublevelContainer.clusters) {
      cluster.blockData.translateOrigin(nudge);
    }
    sublevelContainer.processBlockChanges(centerOfMass);
    _previousCenterOfMass.setFrom(centerOfMass);
  }

  /// `applyLift`: the material lift, clamped so it cannot exceed the weight.
  void applyLift(
    Vector3d localGravity,
    Vector3d linearImpulse,
    Vector3d angularImpulse,
    double timeStep,
  ) {
    var totalForce = 0.0;
    _totalWeightedForce.zero();

    for (final container in containers) {
      for (final cluster in container.clusters) {
        final material = cluster.material;
        if (material.liftStrength == 0) continue;

        var clusterForce = material.liftStrength;
        if (material.scaleWithPressure) {
          clusterForce *= cluster.blockData.getPressureScale();
        }

        final weightedForce = clusterForce * cluster.blockData.totalScale;
        _trueWeightedClusterPosition(container, cluster, _weightedPositionTemp);

        if (material.preventSelfLift) {
          totalForce += weightedForce;
          _totalWeightedForce.fma(clusterForce, _weightedPositionTemp);
        } else {
          linearImpulse.fma(-weightedForce * timeStep, localGravity);

          if (_tracksIndividualForces) {
            final group = _queuedGroup(levitationGroup);
            _recordForce(
              container,
              cluster,
              group,
              Vector3d(localGravity.x, localGravity.y, localGravity.z).mul(-weightedForce * timeStep),
            );
          }

          localGravity.crossInto(_weightedPositionTemp, _torqueTemp);
          angularImpulse.fma(clusterForce * timeStep, _torqueTemp);
        }
      }
    }

    if (totalForce <= 0) return;

    _totalWeightedForce.div(totalForce);
    _averageForcePos.setFrom(_totalWeightedForce);

    _liftingForce.setFrom(localGravity).mul(-totalForce);
    _averageForcePos.crossInto(_liftingForce, _liftingTorque);

    _body.inverseInertiaTensor.transform(_liftingTorque, _torqueTemp);
    _torqueTemp.crossInto(_averageForcePos, _totalAcceleration);
    _totalAcceleration.fma(1 / _body.mass, _liftingForce);

    var scaleFactor = -localGravity.lengthSquared / localGravity.dot(_totalAcceleration);
    if (scaleFactor.isNaN) scaleFactor = 0;
    if (scaleFactor > 1) scaleFactor = 1;

    _liftingForce.mul(scaleFactor);
    _liftingTorque.mul(scaleFactor);

    if (_tracksIndividualForces) {
      final group = _queuedGroup(levitationGroup);
      for (final container in containers) {
        for (final cluster in container.clusters) {
          final material = cluster.material;
          final force = Vector3d(localGravity.x, localGravity.y, localGravity.z).mul(
            timeStep * -cluster.blockData.totalScale * material.liftStrength,
          );
          force.mul(scaleFactor);
          _recordForce(container, cluster, group, force);
        }
      }
    }

    linearImpulse.fma(timeStep, _liftingForce);
    angularImpulse.fma(timeStep, _liftingTorque);
  }

  void _recordForce(
    FloatingClusterContainer container,
    FloatingBlockCluster cluster,
    QueuedForceGroup forceGroup,
    Vector3d force,
  ) {
    final position = _trueWeightedClusterPosition(container, cluster, Vector3d())
      ..div(cluster.blockData.totalScale)
      ..add(_body.centerOfMass);
    forceGroup.recordPointForce(position, force);
  }

  Vector3d _trueWeightedClusterPosition(
    FloatingClusterContainer container,
    FloatingBlockCluster cluster,
    Vector3d dest,
  ) {
    container.rotationOffset.transform(cluster.blockData.weightedPosition, dest);
    return dest.fma(cluster.blockData.totalScale, container.positionOffset);
  }

  /// `applyFriction`: the anisotropic drag of one cluster.
  void applyFriction(
    FloatingClusterContainer container,
    FloatingBlockCluster cluster,
    Vector3d localGravity,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d frictionForce,
    Vector3d frictionTorque,
  ) {
    final material = cluster.material;
    final data = cluster.blockData;

    var frictionScale = 1.0;
    if (material.scaleWithGravity) frictionScale = localGravity.length;
    if (material.scaleWithPressure) frictionScale *= data.getPressureScale();

    var speedScale = 3 / (material.transitionSpeed * material.transitionSpeed);
    if (material.transitionSpeed == 0) speedScale = 0;

    _totalAngularVelocity.setFrom(angularVelocity).add(container.angularVelocity);
    _trueWeightedClusterPosition(container, cluster, _clusterCenter).div(data.totalScale);

    data.outerProduct.scaleInto(1 / data.totalScale, _averagePositionMatrix);

    // Rotate the average position matrix by the container rotation.
    _containerRotation.setFromQuaternion(container.rotationOffset);
    _averagePositionMatrix.mulLocal(_containerRotation);
    _averagePositionMatrix.mul(Matrix3d.copy(_containerRotation)..transpose());

    _averagePositionMatrix.invertInto(_averagePositionMatrixInverse);
    _shiftedPositionMatrixInverse.setFrom(_averagePositionMatrixInverse);
    Matrix3d.fmaInertiaTensor(_totalAngularVelocity, speedScale, _shiftedPositionMatrixInverse);
    _shiftedPositionMatrixInverse.invertInto(_shiftedPositionMatrix);

    // Velocity of the centre of lift, in local space.
    angularVelocity.crossInto(_clusterCenter, _meanVelocity);
    container.rotationOffset
        .transform(data.weightedPosition, _rotatedPos)
        .div(data.totalScale);
    final extraContainerVelocity = Vector3d();
    container.angularVelocity.crossInto(_rotatedPos, extraContainerVelocity);
    _meanVelocity.add(linearVelocity).add(container.velocity).add(extraContainerVelocity);

    // Centre of the shifted position distribution, variance
    // shiftedPositionMatrix.
    _totalAngularVelocity.crossInto(_meanVelocity, _shiftedCenter).mul(speedScale);
    _shiftedPositionMatrix.transform(_shiftedCenter, _shiftedCenter);

    var slowDragScale = math.sqrt(
      _shiftedPositionMatrix.determinant() / _averagePositionMatrix.determinant(),
    );
    slowDragScale *= math.exp(
      -0.5 *
          (speedScale * _meanVelocity.dot(_meanVelocity) -
              Matrix3d.multiplyInnerProduct(_shiftedCenter, _shiftedPositionMatrixInverse, _shiftedCenter)),
    );
    if (material.transitionSpeed == 0) slowDragScale = 0;
    if (slowDragScale.isNaN) slowDragScale = 0;

    // The drag matrices scale forces in their vertical and horizontal parts.
    _gravityMatrix(
      localGravity,
      material.slowVerticalFriction,
      material.slowHorizontalFriction,
      _slowDragMatrix,
    ).scale(data.totalScale * frictionScale * slowDragScale);

    _gravityMatrix(
      localGravity,
      material.fastVerticalFriction,
      material.fastHorizontalFriction,
      _fastDragMatrix,
    ).scale(data.totalScale * frictionScale);

    final cross = Vector3d();
    _totalAngularVelocity.crossInto(_shiftedCenter, cross);
    cross.add(_meanVelocity);
    _slowDragMatrix.transform(cross, _linearSlowDrag);
    _fastDragMatrix.transform(_meanVelocity, frictionForce).add(_linearSlowDrag);

    _clusterCenter.crossInto(frictionForce, frictionTorque);
    _shiftedCenter.crossInto(_linearSlowDrag, cross);
    frictionTorque.add(cross);

    _tempTorqueMatrix.makeZero();
    _matrixThingy(_averagePositionMatrix, _fastDragMatrix, _tempTorqueMatrix);
    _matrixThingy(_shiftedPositionMatrix, _slowDragMatrix, _tempTorqueMatrix);
    _tempTorqueMatrix.transform(_totalAngularVelocity, cross);
    frictionTorque.add(cross);
  }

  /// `matrixThingy(X, Y, out)`: `out += trace(X)·Y + trace(Y)·X − X·Y − Y·X`.
  void _matrixThingy(Matrix3d x, Matrix3d y, Matrix3d out) {
    y.mulInto(x, _yx);
    final traceX = x.trace();
    final traceY = y.trace();
    final traceYX = _yx.trace();

    _traceMatrix.makeIdentity().scale(traceX).subInto(x, _x2);
    _traceMatrix.makeIdentity().scale(traceY).subInto(y, _y2);
    _traceMatrix.makeIdentity().scale(traceYX).subInto(_yx, _yx);

    _x2.mul(_y2);
    out.add(_x2).sub(_yx);
  }

  /// `getGravityMatrix(g, verticalDrag, horizontalDrag, target)`.
  Matrix3d _gravityMatrix(
    Vector3d g,
    double verticalDrag,
    double horizontalDrag,
    Matrix3d target,
  ) {
    if (g.lengthSquared > 0.00001) {
      Matrix3d.setOuterProduct(
        g,
        g,
        (horizontalDrag - verticalDrag) / g.dot(g),
        target,
      );
    } else {
      target.makeIdentity();
    }
    target
      ..m00 -= horizontalDrag
      ..m11 -= horizontalDrag
      ..m22 -= horizontalDrag;
    return target;
  }

  bool get _tracksIndividualForces => subLevel?.isTrackingIndividualQueuedForces() ?? false;

  QueuedForceGroup _queuedGroup(ForceGroup group) {
    final level = subLevel;
    if (level == null) {
      throw StateError(
        'FloatingBlockController: recording ${group.name} forces needs the '
        'sub-level that owns the queue; construct the controller with one.',
      );
    }
    return level.getOrCreateQueuedForceGroup(group);
  }

  ServerSubLevel _subLevelOrThrow() {
    final level = subLevel;
    if (level == null) {
      throw StateError(
        'FloatingBlockController: sampling air pressure needs a sub-level; '
        'construct the controller with one, or resolve materials without '
        'scaleWithPressure.',
      );
    }
    return level;
  }

  /// The orientation of the body in world space.
  Quaterniond get _bodyOrientation => subLevel?.logicalPose.orientation() ?? Quaterniond();

  /// `addFloatingBlock(state, pos)` on the sub-level container.
  void addFloatingBlock(String state, Vector3d pos) => sublevelContainer.addFloatingBlock(state, pos);

  /// `removeFloatingBlock(state, pos)` on the sub-level container.
  void removeFloatingBlock(String state, Vector3d pos) =>
      sublevelContainer.removeFloatingBlock(state, pos);

  /// `queueAddFloatingBlock(state, pos)`.
  void queueAddFloatingBlock(String state, (int, int, int) pos) =>
      sublevelContainer.queueAddFloatingBlock(state, pos);

  /// `queueRemoveFloatingBlock(state, pos)`.
  void queueRemoveFloatingBlock(String state, (int, int, int) pos) =>
      sublevelContainer.queueRemoveFloatingBlock(state, pos);
}

/// Adapts a [ServerSubLevel] plus the block-property table to a
/// [FloatingBlockBody].
final class SubLevelFloatingBlockBody implements FloatingBlockBody {
  final ServerSubLevel subLevel;
  final PhysicsBlockPropertiesTable properties;
  final double Function(Vector3d worldPosition) pressure;

  /// The body's inverse inertia tensor, read from the mass tracker.
  final Matrix3d Function() inverseInertia;

  /// The body's mass, read from the mass tracker.
  final double Function() bodyMass;

  SubLevelFloatingBlockBody({
    required this.subLevel,
    required this.properties,
    required this.pressure,
    required this.inverseInertia,
    required this.bodyMass,
  });

  @override
  Vector3d get centerOfMass {
    final tracker = subLevel.massTracker;
    if (tracker == null) return Vector3d();
    return tracker.getCenterOfMass();
  }

  @override
  double get mass => bodyMass();

  @override
  Matrix3d get inverseInertiaTensor => inverseInertia();

  @override
  FloatingBlockMaterial? materialOf(String state) {
    final id = properties.floatingMaterialOf(state);
    return id == null ? null : FloatingBlockMaterialDataHandler.material(id);
  }

  @override
  double floatingScaleOf(String state) => properties.floatingScaleOf(state);

  @override
  double pressureAt(Vector3d worldPosition) => pressure(worldPosition);
}
