// `dev.ryanhcode.sable.api.physics.mass.MassTracker` and
// `MergedMassTracker`: the mass and inertia tensor of a sub-level.
//
// Java builds the tracker once from the plot bounds (`MassTracker.build`), then
// keeps it up to date block by block (`MassTracker.addBlockMass`), and merges
// the kinematic contraptions mounted on the sub-level into it every physics
// substep (`MergedMassTracker.update`).
//
// The host owns the collision shapes, so the per-block inputs are injected:
// [MassTracker.blockMass], [MassTracker.blockInertia], [MassTracker.isSolid]
// and [MassTracker.blockCenterOfMass] default to "every non-air block is a
// solid unit cube with mass 1 and its centre at the block centre", and the
// plugin replaces them with the block-property table and the shape queries.
// This is the same split as `SubLevelPhysicsSystem.blockMass`/`blockInertia`.
//
// Pure: no host imports.
import '../api/physics.dart';
import '../math/bounding_box.dart';
import '../math/matrix3.dart';
import '../math/vector.dart';
import 'server_sub_level.dart';

/// A mass tracker that can take block deltas.
///
/// Java's `MassTracker.addBlockMass(blockGetter, state, pos, mass, inertia)`;
/// the level-side inputs are the static hooks on [MassTracker].
abstract interface class MutableMassTracker {
  /// `addBlockMass`: [mass] is negative to remove a block.
  void addBlockMass(
    String state,
    (int, int, int) pos,
    double mass,
    (double, double, double)? inertia,
  );
}

/// `MassTracker`: the mass, centre of mass and inertia tensor of a sub-level's
/// own blocks (contraptions are merged in by [MergedMassTracker]).
final class MassTracker implements MassData, MutableMassTracker {
  /// The mass of the sub-level [kg] (`MassTracker.java:86`).
  double _mass;

  /// `1 / mass` [1/kg].
  double _inverseMass;

  /// The inertia tensor about the centre of mass [kg·m²].
  final Matrix3d _inertiaTensor;

  /// `inertiaTensor.invert()`.
  final Matrix3d _inverseInertiaTensor;

  /// The centre of mass in plot coordinates, or `null` for an empty tracker.
  Vector3d? _centerOfMass;

  final BoundingBox3ic? _bounds;

  /// The sub-level the tracker belongs to, for the per-block hooks.
  final ServerSubLevel? _owner;

  MassTracker._(
    this._mass,
    this._inverseMass,
    this._inertiaTensor,
    this._inverseInertiaTensor,
    this._centerOfMass,
    this._bounds,
    this._owner,
  );

  /// An empty tracker (`new MassTracker()`): zero mass, no centre of mass.
  MassTracker() : this._(0.0, 0.0, Matrix3d.zero(), Matrix3d.zero(), null, null, null);

  // ---- Injected block inputs ---------------------------------------------

  /// `PhysicsBlockPropertyHelper.getMass`: the mass of [state] [kg].
  ///
  /// The default treats every block as 1 kg, matching the system's default
  /// hook (`SubLevelPhysicsSystem.blockMass`); the plugin installs the real
  /// block-property table.
  static double Function(ServerSubLevel subLevel, String state) blockMass = (_, _) => 1.0;

  /// `PhysicsBlockPropertyHelper.getInertia`: the block's own inertia
  /// `(Ix, Iy, Iz)` in `kg·m²`, or `null` for the unit-cube default.
  static (double, double, double)? Function(ServerSubLevel subLevel, String state) blockInertia =
      (_, _) => null;

  /// `VoxelNeighborhoodState.isSolid`: whether [state] takes part in physics.
  ///
  /// Java also requires a non-empty collision shape; the plot chunk API only
  /// exposes the block key, so the default is "not air" and the plugin refines
  /// it with the shape query.
  static bool Function(ServerSubLevel subLevel, String state) isSolid =
      (_, state) => state != 'minecraft:air';

  /// `MassTracker.BLOCK_CENTER_OF_MASS`: the centre of the block's collision
  /// shape, relative to the block's lower corner.
  ///
  /// The default is the block centre, which is also Java's fallback for a full
  /// block or an empty shape.
  static Vector3d Function(ServerSubLevel subLevel, String state) blockCenterOfMass =
      (_, _) => Vector3d(0.5, 0.5, 0.5);

  // ---- Construction -------------------------------------------------------

  /// `MassTracker.build(blockGetter, bounds)`.
  ///
  /// Scans the plot bounds, adds every solid block's mass at its centre of
  /// mass, then computes the inertia tensor about the structure's centre of
  /// mass. A structure without a solid block yields an invalid tracker, exactly
  /// like Java's empty `MassTracker` (`MassTracker.java:127-134`).
  ///
  /// A structure whose solid blocks all have zero mass is also invalid; Java
  /// would divide by zero there, and a massless body cannot be simulated.
  factory MassTracker.build(ServerSubLevel subLevel) {
    final bounds = subLevel.getPlot().getBoundingBox();
    final boundsCopy = BoundingBox3i.copy(bounds);

    if (bounds.volume() <= 0) {
      return MassTracker._(0.0, 0.0, Matrix3d.zero(), Matrix3d.zero(), null, boundsCopy, subLevel);
    }

    var totalMass = 0.0;
    final weightedCenter = Vector3d();
    var blockCount = 0;

    for (var x = bounds.minX; x <= bounds.maxX; x++) {
      for (var y = bounds.minY; y <= bounds.maxY; y++) {
        for (var z = bounds.minZ; z <= bounds.maxZ; z++) {
          final state = _stateAt(subLevel, x, y, z);
          if (!isSolid(subLevel, state)) continue;

          final mass = blockMass(subLevel, state);
          if (mass == 0.0) continue;

          final center = blockCenterOfMass(subLevel, state);
          weightedCenter.fma(mass, Vector3d(x + center.x, y + center.y, z + center.z));
          totalMass += mass;
          blockCount++;
        }
      }
    }

    if (blockCount == 0 || totalMass <= 0.0) {
      return MassTracker._(0.0, 0.0, Matrix3d.zero(), Matrix3d.zero(), null, boundsCopy, subLevel);
    }

    weightedCenter.div(totalMass);

    final inertia = Matrix3d.zero();
    for (var x = bounds.minX; x <= bounds.maxX; x++) {
      for (var y = bounds.minY; y <= bounds.maxY; y++) {
        for (var z = bounds.minZ; z <= bounds.maxZ; z++) {
          final state = _stateAt(subLevel, x, y, z);
          if (!isSolid(subLevel, state)) continue;

          final mass = blockMass(subLevel, state);
          if (mass == 0.0) continue;

          final center = blockCenterOfMass(subLevel, state);
          final offset = Vector3d(
            x + center.x,
            y + center.y,
            z + center.z,
          ).sub(weightedCenter);
          addBlockInertia(offset, mass, blockInertia(subLevel, state), inertia);
        }
      }
    }

    return MassTracker._(
      totalMass,
      1.0 / totalMass,
      inertia,
      Matrix3d.copy(inertia)..invert(),
      weightedCenter,
      boundsCopy,
      subLevel,
    );
  }

  /// The block state string at the plot position, or air when the chunk is not
  /// loaded.
  static String _stateAt(ServerSubLevel subLevel, int x, int y, int z) {
    final plot = subLevel.getPlot();
    final holder = plot.getChunkHolder(plot.toLocal((x >> 4, z >> 4)));
    if (holder == null) return 'minecraft:air';
    return holder.chunk.blockAt(x & 15, y, z & 15);
  }

  // ---- Mutation -----------------------------------------------------------

  /// `MassTracker.addBlockMass(blockGetter, state, blockPos, blockMass,
  /// blockInertia)`: adds the mass of one block; a negative [blockMass] removes
  /// it.
  @override
  void addBlockMass(
    String state,
    (int, int, int) pos,
    double blockMass,
    (double, double, double)? inertia,
  ) {
    final owner = _owner;
    final oldMass = _mass;
    final newMass = oldMass + blockMass;

    final center = owner == null ? Vector3d(0.5, 0.5, 0.5) : blockCenterOfMass(owner, state);
    final blockCenter = Vector3d(
      pos.$1 + center.x,
      pos.$2 + center.y,
      pos.$3 + center.z,
    );

    final current = _centerOfMass;
    if (current == null) {
      _centerOfMass = Vector3d.copy(blockCenter);
    }

    final blockCenterFromCom = Vector3d.copy(blockCenter).sub(_centerOfMass!);
    addBlockInertia(blockCenterFromCom, blockMass, inertia, _inertiaTensor);

    _mass = newMass;
    _inverseMass = 1.0 / newMass;

    moveCenterOfMass(
      Vector3d.copy(_centerOfMass!)
          .mul(oldMass)
          .add(blockCenter.mul(blockMass))
          .div(newMass),
    );
  }

  /// `MassTracker.moveCenterOfMass(newCenterOfMass)`: shifts the tensor by the
  /// parallel-axis term and re-inverts it (`MassTracker.java:225-248`).
  void moveCenterOfMass(Vector3d newCenterOfMass) {
    final current = _centerOfMass;
    if (current == null) {
      _centerOfMass = Vector3d.copy(newCenterOfMass);
      return;
    }

    final diff = Vector3d.copy(newCenterOfMass).sub(current);
    final outerProduct = Matrix3d(
      diff.x * diff.x,
      diff.x * diff.y,
      diff.x * diff.z,
      diff.y * diff.x,
      diff.y * diff.y,
      diff.y * diff.z,
      diff.z * diff.x,
      diff.z * diff.y,
      diff.z * diff.z,
    );

    final inertia = Matrix3d.identity().scale(diff.lengthSquared).sub(outerProduct).scale(_mass);

    _inertiaTensor.sub(inertia);
    _inverseInertiaTensor.setFrom(Matrix3d.copy(_inertiaTensor)..invert());
    _centerOfMass = Vector3d.copy(newCenterOfMass);
  }

  /// `MassTracker.addBlockInertia`: the block's own inertia (a cube of
  /// [blockMass] unless the block sets `sable:inertia`) plus
  /// `m·(|r|²·I − r·rᵀ)` (`MassTracker.java:201-216`).
  static void addBlockInertia(
    Vector3d offset,
    double blockMass,
    (double, double, double)? blockInertia,
    Matrix3d dest,
  ) {
    if (blockInertia == null) {
      final cube = blockMass / 6.0;
      dest
        ..m00 += cube
        ..m11 += cube
        ..m22 += cube;
    } else {
      dest
        ..m00 += blockInertia.$1 * blockMass
        ..m11 += blockInertia.$2 * blockMass
        ..m22 += blockInertia.$3 * blockMass;
    }

    Matrix3d.fmaInertiaTensor(offset, blockMass, dest);
  }

  // ---- MassData -----------------------------------------------------------

  @override
  double getMass() => _mass;

  @override
  double getInverseMass() => _inverseMass;

  @override
  Matrix3d getInertiaTensor() => _inertiaTensor;

  @override
  Matrix3d getInverseInertiaTensor() => _inverseInertiaTensor;

  @override
  Vector3d getCenterOfMass() {
    final center = _centerOfMass;
    if (center == null) {
      throw StateError('MassTracker: the structure has no solid blocks');
    }
    return center;
  }

  /// The centre of mass, or `null` when the tracker is invalid.
  Vector3d? get centerOfMassOrNull => _centerOfMass;

  @override
  bool isInvalid() => _mass <= 0.0 || _centerOfMass == null;

  @override
  BoundingBox3ic? getBounds() => _bounds;
}

/// `MergedMassTracker`: the sub-level's mass properties including every
/// kinematic contraption mounted on it.
final class MergedMassTracker implements MassData {
  /// The tracker for the sub-level's own blocks.
  final MassTracker selfTracker;

  /// The sub-level whose plot's contraptions are merged in.
  final ServerSubLevel subLevel;

  double _mass = 0.0;
  final Matrix3d _inertiaTensor = Matrix3d.zero();
  double _inverseMass = 0.0;
  final Matrix3d _inverseInertiaTensor = Matrix3d.zero();
  Vector3d? _centerOfMass;

  double _lastMass = 0.0;
  Vector3d? _lastCenterOfMass;
  Matrix3d? _lastInertiaTensor;

  MergedMassTracker(this.subLevel, this.selfTracker);

  /// `MergedMassTracker.update(partialPhysicsTick)`: recomputes the merged mass
  /// properties.
  ///
  /// Returns whether the result changed since the last update, which is when
  /// Java's `uploadData` would push it to the pipeline
  /// (`MergedMassTracker.java:105-126`). The upload itself is the physics
  /// system's job: it owns the pipeline. Unlike Rapier, Jolt keeps the body
  /// origin at the plot origin and only stores the centre of mass as a shape
  /// offset, so no teleport compensation is needed.
  bool update(double partialPhysicsTick) {
    if (selfTracker.centerOfMassOrNull == null) {
      return false;
    }

    final contraptions = subLevel.getPlot().getContraptions();

    _mass = selfTracker.getMass();
    _centerOfMass = Vector3d.copy(selfTracker.getCenterOfMass()).mul(_mass);

    for (final contraption in contraptions) {
      final contraptionMassData = contraption.sable$getMassTracker();
      _mass += contraptionMassData.getMass();
      _centerOfMass!.fma(
        contraptionMassData.getMass(),
        contraption.sable$getPosition(partialPhysicsTick),
      );
    }

    _centerOfMass!.mul(1.0 / _mass);

    _inertiaTensor.setFrom(selfTracker.getInertiaTensor());
    final localShift = Vector3d.copy(_centerOfMass!).sub(selfTracker.getCenterOfMass());

    // Nudge the tensor from the sub-level's centre of mass to the merged one.
    if (localShift.lengthSquared > 0.0) {
      Matrix3d.fmaInertiaTensor(localShift, selfTracker.getMass(), _inertiaTensor);
    }

    for (final contraption in contraptions) {
      final contraptionMassData = contraption.sable$getMassTracker();

      final localPos = Vector3d.copy(
        contraption.sable$getPosition(partialPhysicsTick),
      ).sub(_centerOfMass!);
      Matrix3d.fmaInertiaTensor(localPos, contraptionMassData.getMass(), _inertiaTensor);

      final orientation = contraption.sable$getOrientation(partialPhysicsTick);

      // `Q⁻¹ * I * Q`: rotate the contraption's local tensor into the plot
      // frame (`MergedMassTracker.java:91-96`).
      final localInertiaTensor = Matrix3d()
        ..setFromQuaternion(Quaterniond.copy(orientation)..conjugate());
      localInertiaTensor.mulLocal(contraptionMassData.getInertiaTensor());
      localInertiaTensor.mulLocal(Matrix3d()..setFromQuaternion(orientation));

      _inertiaTensor.add(localInertiaTensor);
    }

    _inverseMass = 1.0 / _mass;
    _inverseInertiaTensor.setFrom(Matrix3d.copy(_inertiaTensor)..invert());

    final changed = _uploadData();
    _setPreviousValues();
    return changed;
  }

  /// `MergedMassTracker.uploadData`'s change test.
  bool _uploadData() {
    final center = _centerOfMass;
    if (center == null) return false;

    return _mass != _lastMass ||
        _lastCenterOfMass == null ||
        _lastInertiaTensor == null ||
        !_sameVector(_lastCenterOfMass!, center) ||
        _lastInertiaTensor! != _inertiaTensor;
  }

  static bool _sameVector(Vector3d a, Vector3d b) => a.x == b.x && a.y == b.y && a.z == b.z;

  /// `MergedMassTracker.setPreviousValues`.
  void _setPreviousValues() {
    final center = _centerOfMass;
    if (center == null) {
      _lastCenterOfMass = null;
      _lastInertiaTensor = null;
    } else {
      _lastCenterOfMass ??= Vector3d();
      _lastInertiaTensor ??= Matrix3d.zero();
      _lastCenterOfMass!.setFrom(center);
      _lastInertiaTensor!.setFrom(_inertiaTensor);
    }
    _lastMass = _mass;
  }

  /// The tracker for just the sub-level's blocks, not the merged masses
  /// (`getSelfMassTracker()`).
  MassTracker getSelfMassTracker() => selfTracker;

  @override
  double getMass() => _mass;

  @override
  double getInverseMass() => _inverseMass;

  @override
  Matrix3d getInertiaTensor() => _inertiaTensor;

  @override
  Matrix3d getInverseInertiaTensor() => _inverseInertiaTensor;

  @override
  Vector3d getCenterOfMass() {
    final center = _centerOfMass;
    if (center == null) {
      throw StateError('MergedMassTracker: the sub-level has no solid blocks');
    }
    return center;
  }

  @override
  bool isInvalid() => _mass <= 0.0 || _centerOfMass == null;

  @override
  BoundingBox3ic? getBounds() => selfTracker.getBounds();
}
