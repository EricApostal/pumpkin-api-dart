// The main Sable <-> Create bridge: a Create contraption entity as a Sable
// `KinematicContraption`.
//
// In Java this is `AbstractContraptionEntityMixin`, which makes
// `AbstractContraptionEntity` implement `KinematicContraption`, builds its mass
// and lift data once, and adds the entity to the sub-level's plot and to the
// physics pipeline. The Dart port keeps the same model: a
// [ContraptionKinematicBody] wraps a contraption entity and answers the
// `KinematicContraption` questions from the contraption's captured blocks.
//
// What the Java mixin does through injection is done here by calling the
// wrapper explicitly:
//
// * the block scan that used to run from `tick` is [ContraptionKinematicBody.build];
// * `setRemoved` is [ContraptionPhysicsBinding.release];
// * `saveWithoutId`'s passenger fix is
//   [ContraptionPhysicsBinding.gatherPassengersForSave];
// * `moveCollidedEntitiesOnDisassembly`'s transforms are
//   [ContraptionDisassemblyTransforms].
//
// Pure: no host imports (the Create contraption classes this file uses are the
// pure ones), so the Dart VM tests can load it.
//
// Java: `...create.contraptions.AbstractContraptionEntityMixin`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState, BlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/entity/contraption_entity.dart';
import 'package:create/src/contraptions/entity/contraption_world.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/bounding_box.dart';
import '../../sublevel/math/matrix3.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/server_level_plot.dart' show LiftProviderContext;
import '../../sublevel/model/server_sub_level.dart';
import '../../sublevel/model/server_sub_level_container.dart';
import '../../sublevel/model/sub_level.dart';
import '../../sublevel/model/sub_level_container.dart';
import '../../sublevel/physics/physics_block_properties.dart';
import '../../sublevel/api/physics.dart' show KinematicContraption, MassData;
import '../../sublevel/api/sub_level_helper.dart';
import '../../sublevel/system/physics_system.dart';
import 'create_blocks.dart';

/// The mass tracker of a contraption: `MassTracker.build` over the contraption's
/// captured blocks.
///
/// Java builds this from `contraption.getContraptionWorld()` and the contraption's
/// local bounds; the scan is the same: for every solid block, add its mass at
/// its centre of mass and its inertia about the structure's centre of mass.
final class ContraptionMassTracker implements MassData {
  /// The total mass, in `kpg`.
  final double mass;

  /// The inertia tensor about the centre of mass, in `kg·m²`.
  final Matrix3d inertiaTensor;

  /// The inverse inertia tensor.
  final Matrix3d inverseInertiaTensor;

  final Vector3d? _centerOfMass;
  final double _inverseMass;
  final BoundingBox3i _bounds;

  ContraptionMassTracker._(
    this.mass,
    this._inverseMass,
    this._centerOfMass,
    this.inertiaTensor,
    this.inverseInertiaTensor,
    this._bounds,
  );

  /// `MassTracker.build(blockGetter, bounds)`.
  ///
  /// [properties] supplies `sable:mass` and `sable:inertia`. A structure without
  /// a solid block yields an invalid tracker, exactly like Java's empty
  /// `MassTracker`.
  factory ContraptionMassTracker.build(
    BlockGetter blockGetter,
    BoundingBox3ic bounds, {
    PhysicsBlockPropertiesTable? properties,
  }) {
    final table = properties ?? PhysicsBlockPropertiesTable();
    final boundsCopy = BoundingBox3i.copy(bounds);

    var totalMass = 0.0;
    final weightedCenter = Vector3d();
    var blockCount = 0;

    void visit(void Function(int x, int y, int z, BState state) action) {
      for (var x = bounds.minX; x <= bounds.maxX; x++) {
        for (var y = bounds.minY; y <= bounds.maxY; y++) {
          for (var z = bounds.minZ; z <= bounds.maxZ; z++) {
            action(x, y, z, blockGetter.stateAt((x, y, z)));
          }
        }
      }
    }

    visit((x, y, z, state) {
      if (!isSolidBlock(blockGetter, (x, y, z), state)) return;

      final blockMass = table.massOf(state.toString(), true);
      final center = blockCenterOfMass(blockGetter, (x, y, z), state);
      weightedCenter.fma(blockMass, Vector3d(x + center.x, y + center.y, z + center.z));
      totalMass += blockMass;
      blockCount++;
    });

    if (blockCount == 0 || totalMass == 0) {
      return ContraptionMassTracker._(0.0, 0.0, null, Matrix3d.zero(), Matrix3d.zero(), boundsCopy);
    }

    weightedCenter.div(totalMass);

    final inertia = Matrix3d.zero();
    visit((x, y, z, state) {
      if (!isSolidBlock(blockGetter, (x, y, z), state)) return;

      final blockMass = table.massOf(state.toString(), true);
      final center = blockCenterOfMass(blockGetter, (x, y, z), state);
      final offset = Vector3d(x + center.x, y + center.y, z + center.z).sub(weightedCenter);
      addBlockInertia(offset, blockMass, table.inertiaOf(state.toString(), true), inertia);
    });

    return ContraptionMassTracker._(
      totalMass,
      1.0 / totalMass,
      weightedCenter,
      inertia,
      Matrix3d.copy(inertia)..invert(),
      boundsCopy,
    );
  }

  /// `VoxelNeighborhoodState.isSolid`: not air and with a collision shape.
  static bool isSolidBlock(BlockGetter blockGetter, Pos pos, BState state) {
    if (state.isAir) return false;
    return !blockGetter.collisionShapeEmpty(pos);
  }

  /// `MassTracker.BLOCK_CENTER_OF_MASS`: the centre of the block's collision
  /// shape, or the block centre when the shape is empty or fills the block.
  static Vector3d blockCenterOfMass(BlockGetter blockGetter, Pos pos, BState state) {
    final custom = CreateCompatBlocks.centerOfMassOf(blockGetter, state);
    if (custom != null) return custom;

    if (state.isAir) return Vector3d(0.5, 0.5, 0.5);
    if (blockGetter.collisionShapeEmpty(pos)) return Vector3d(0.5, 0.5, 0.5);
    if (blockGetter.isCollisionShapeFullBlock(pos)) return Vector3d(0.5, 0.5, 0.5);

    // The union of the shape boxes, clipped to the unit block, as
    // `shape.bounds().intersect(UNIT_BOUNDS)` does.
    final boxes = blockGetter.collisionBoxes(pos);
    var minX = 1.0, minY = 1.0, minZ = 1.0, maxX = 0.0, maxY = 0.0, maxZ = 0.0;
    for (final box in boxes) {
      final boxMinX = math.max(0.0, math.min(1.0, box.minX));
      final boxMinY = math.max(0.0, math.min(1.0, box.minY));
      final boxMinZ = math.max(0.0, math.min(1.0, box.minZ));
      final boxMaxX = math.max(0.0, math.min(1.0, box.maxX));
      final boxMaxY = math.max(0.0, math.min(1.0, box.maxY));
      final boxMaxZ = math.max(0.0, math.min(1.0, box.maxZ));
      minX = math.min(minX, boxMinX);
      minY = math.min(minY, boxMinY);
      minZ = math.min(minZ, boxMinZ);
      maxX = math.max(maxX, boxMaxX);
      maxY = math.max(maxY, boxMaxY);
      maxZ = math.max(maxZ, boxMaxZ);
    }

    return Vector3d((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5);
  }

  /// `MassTracker.addBlockInertia`: the block's own inertia (a cube of
  /// [blockMass] unless the block sets `sable:inertia`) plus `m·(|r|²·I − r·rᵀ)`.
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

  @override
  Vector3d getCenterOfMass() {
    final center = _centerOfMass;
    if (center == null) {
      throw StateError('ContraptionMassTracker: the contraption has no solid blocks');
    }
    return center;
  }

  /// The centre of mass, or `null` when the tracker is invalid.
  Vector3d? get centerOfMassOrNull => _centerOfMass;

  @override
  double getInverseMass() => _inverseMass;

  @override
  bool isInvalid() => _centerOfMass == null;

  @override
  BoundingBox3ic getBounds() => _bounds;
}

/// A `BlockGetter` over a contraption's captured blocks for the case where the
/// contraption has no level to resolve shapes against
/// (`Contraption.getContraptionWorld()` when `levelForColliders` is gone).
///
/// Every non-air block is treated as a full cube: without a block registry a
/// shape cannot be resolved, and a full cube is the shape of the blocks that
/// make up a moving structure. When the contraption has a level, the bridge
/// uses [ContraptionWorld] instead, which asks the level for the real shapes.
final class CapturedBlocksGetter extends BlockGetter {
  final Contraption contraption;

  CapturedBlocksGetter(this.contraption);

  @override
  BState stateAt(Pos p) => contraption.blocks[p]?.state ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => !stateAt(p).isAir;

  @override
  List<BlockBox> collisionBoxes(Pos p) => stateAt(p).isAir ? const [] : const [BlockBox.unit];

  @override
  bool supportShapeEmpty(Pos p) => stateAt(p).isAir;

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;
}

/// A Create contraption entity as a Sable kinematic body.
///
/// Java's mixin stores the same fields on the entity; here they are the
/// wrapper's state, built once by [build] and released by
/// [ContraptionPhysicsBinding.release].
final class ContraptionKinematicBody implements KinematicContraption {
  /// The contraption entity this body belongs to.
  final AbstractContraptionEntity entity;

  /// The contraption the entity carries.
  final Contraption contraption;

  /// The block getter of the contraption.
  final BlockGetter blockGetter;

  /// The local bounds of the contraption, `null` when it is empty.
  final BoundingBox3i? localBounds;

  /// The mass and inertia of the contraption, `null` when it has no solid block.
  final ContraptionMassTracker? massTracker;

  /// The lift providers of the contraption, by block position.
  final Map<Pos, LiftProviderContext> liftProviders;

  final Vector3d _cachedGlobalPosition = Vector3d();

  ContraptionKinematicBody._(
    this.entity,
    this.contraption,
    this.blockGetter,
    this.localBounds,
    this.massTracker,
    this.liftProviders,
  );

  /// `sable$buildProperties`: scans the captured blocks once.
  ///
  /// Returns `null` when the contraption is empty (Java quits before adding it
  /// to the plot or the pipeline).
  static ContraptionKinematicBody? build(AbstractContraptionEntity entity) {
    final contraption = entity.contraption;
    if (contraption == null) return null;

    final parent = contraption.levelForColliders;
    final BlockGetter getter = parent == null
        ? CapturedBlocksGetter(contraption)
        : ContraptionWorld(parent, contraption);

    BoundingBox3i? localBounds;
    final liftProviders = <Pos, LiftProviderContext>{};

    for (final entry in contraption.blocks.entries) {
      final blockPos = entry.key;
      final state = entry.value.state;
      if (state.isAir) continue;

      if (localBounds == null) {
        localBounds = BoundingBox3i.values(
          blockPos.$1,
          blockPos.$2,
          blockPos.$3,
          blockPos.$1,
          blockPos.$2,
          blockPos.$3,
        );
      } else {
        localBounds.expandToValues(blockPos.$1, blockPos.$2, blockPos.$3);
      }

      final provider = CreateCompatBlocks.liftProviderAt(blockPos, state);
      if (provider != null) {
        liftProviders[blockPos] = LiftProviderContext(blockPos, state.toString(), (
          provider.normal.x,
          provider.normal.y,
          provider.normal.z,
        ));
      }
    }

    if (localBounds == null) return null;

    final mass = ContraptionMassTracker.build(getter, localBounds);
    if (mass.isInvalid()) return null;

    return ContraptionKinematicBody._(entity, contraption, getter, localBounds, mass, liftProviders);
  }

  @override
  void sable$getLocalBounds(BoundingBox3i bounds) {
    final local = localBounds;
    if (local == null) return;
    bounds.setFrom(local);
  }

  @override
  Object sable$blockGetter() => blockGetter;

  @override
  MassData sable$getMassTracker() {
    final mass = massTracker;
    if (mass == null) {
      throw StateError('ContraptionKinematicBody: the contraption has no mass tracker');
    }
    return mass;
  }

  /// The mass tracker, or `null` when the contraption is empty.
  ContraptionMassTracker? get mass => massTracker;

  /// `KinematicContraption.sable$getLocalPose`: the contraption's pose, with the
  /// mass centre as the rotation point.
  @override
  Pose3d sable$getLocalPose(Pose3d dest, double partialTick) {
    dest.rotationPoint().setFrom(sable$getMassTracker().getCenterOfMass());
    dest.position().setFrom(sable$getPosition(partialTick));
    dest.orientation().setFrom(sable$getOrientation(partialTick));
    dest.scale().set(1.0, 1.0, 1.0);
    return dest;
  }

  @override
  Map<(int, int, int), Object> sable$liftProviders() =>
      {for (final entry in liftProviders.entries) entry.key: entry.value};

  @override
  bool sable$isValid() => !entity.host.isRemoved;

  @override
  bool sable$shouldCollide() => true;

  /// `sable$getPosition(partialTick)`: the centre of mass, rotated by the entity
  /// and moved to the interpolated anchor.
  @override
  Vector3d sable$getPosition(double partialTick) {
    final mass = massTracker;
    if (mass == null || mass.isInvalid()) {
      throw StateError('ContraptionKinematicBody: the contraption has no centre of mass');
    }

    final local = mass.getCenterOfMass();
    var vec = (local.x, local.y, local.z);
    final anchor = lerpVec3(entity.getPrevAnchorVec(), entity.getAnchorVec(), partialTick);
    const rotationOffset = (0.5, 0.5, 0.5);

    vec = (vec.$1 - rotationOffset.$1, vec.$2 - rotationOffset.$2, vec.$3 - rotationOffset.$3);
    vec = entity.applyRotation(vec, partialTick);
    vec = (vec.$1 + rotationOffset.$1, vec.$2 + rotationOffset.$2, vec.$3 + rotationOffset.$3);
    vec = (vec.$1 + anchor.$1, vec.$2 + anchor.$2, vec.$3 + anchor.$3);

    return _cachedGlobalPosition.set(vec.$1, vec.$2, vec.$3);
  }

  /// `sable$getOrientation(partialTick)`: the rotation the entity applies to the
  /// three basis vectors, as a quaternion.
  @override
  Quaterniond sable$getOrientation(double partialTick) {
    final matrix = Matrix3d.identity();

    for (var column = 0; column < 3; column++) {
      final Vec3 axis = switch (column) {
        0 => (1.0, 0.0, 0.0),
        1 => (0.0, 1.0, 0.0),
        _ => (0.0, 0.0, 1.0),
      };
      final transformed = entity.applyRotation(axis, partialTick);
      switch (column) {
        case 0:
          matrix.set(
            transformed.$1,
            matrix.m01,
            matrix.m02,
            transformed.$2,
            matrix.m11,
            matrix.m12,
            transformed.$3,
            matrix.m21,
            matrix.m22,
          );
        case 1:
          matrix.set(
            matrix.m00,
            transformed.$1,
            matrix.m02,
            matrix.m10,
            transformed.$2,
            matrix.m12,
            matrix.m20,
            transformed.$3,
            matrix.m22,
          );
        default:
          matrix.set(
            matrix.m00,
            matrix.m01,
            transformed.$1,
            matrix.m10,
            matrix.m11,
            transformed.$2,
            matrix.m20,
            matrix.m21,
            transformed.$3,
          );
      }
    }

    return quaternionFromRotationMatrix(matrix);
  }

  /// `Vec3.lerp`.
  static Vec3 lerpVec3(Vec3 from, Vec3 to, double t) =>
      (from.$1 + (to.$1 - from.$1) * t, from.$2 + (to.$2 - from.$2) * t, from.$3 + (to.$3 - from.$3) * t);
}

/// The rotation matrix of a quaternion: JOML's
/// `Matrix3d.getNormalizedRotation(Quaterniond)`, i.e. the normalized
/// matrix-to-quaternion conversion.
///
/// The matrix built by [ContraptionKinematicBody.sable$getOrientation] is
/// orthonormal by construction (three rotated basis vectors).
Quaterniond quaternionFromRotationMatrix(Matrix3d m) {
  final trace = m.m00 + m.m11 + m.m22;

  if (trace > 0) {
    final s = 0.5 / math.sqrt(trace + 1.0);
    return Quaterniond(
      (m.m21 - m.m12) * s,
      (m.m02 - m.m20) * s,
      (m.m10 - m.m01) * s,
      0.25 / s,
    );
  }

  if (m.m00 > m.m11 && m.m00 > m.m22) {
    final s = 2.0 * math.sqrt(1.0 + m.m00 - m.m11 - m.m22);
    return Quaterniond(
      0.25 * s,
      (m.m01 + m.m10) / s,
      (m.m02 + m.m20) / s,
      (m.m21 - m.m12) / s,
    );
  }

  if (m.m11 > m.m22) {
    final s = 2.0 * math.sqrt(1.0 + m.m11 - m.m00 - m.m22);
    return Quaterniond(
      (m.m01 + m.m10) / s,
      0.25 * s,
      (m.m12 + m.m21) / s,
      (m.m02 - m.m20) / s,
    );
  }

  final s = 2.0 * math.sqrt(1.0 + m.m22 - m.m00 - m.m11);
  return Quaterniond(
    (m.m02 + m.m20) / s,
    (m.m12 + m.m21) / s,
    0.25 * s,
    (m.m10 - m.m01) / s,
  );
}

/// Adds a contraption to its sub-level's plot and to the physics pipeline, and
/// removes it again: `sable$contraptionInitialize`, `sable$addToPlot`,
/// `sable$addToPipeline`, `setRemoved` and `saveWithoutId` of the Java mixin.
final class ContraptionPhysicsBinding {
  final ContraptionKinematicBody body;

  /// The sub-level the contraption is on.
  final ServerSubLevel subLevel;

  /// The level the sub-level belongs to.
  final SableLevel level;

  bool _released = false;

  ContraptionPhysicsBinding._(this.body, this.subLevel, this.level);

  /// Builds the body and registers it on [subLevel].
  ///
  /// Returns `null` when the contraption is empty: Java's
  /// `sable$contraptionInitialize` also quits for an empty contraption.
  static ContraptionPhysicsBinding? attach(
    AbstractContraptionEntity entity,
    ServerSubLevel subLevel, {
    PhysicsBlockPropertiesTable? properties,
  }) {
    final body = ContraptionKinematicBody.build(entity);
    if (body == null) return null;

    final binding = ContraptionPhysicsBinding._(body, subLevel, subLevel.getLevel());
    binding._register();
    return binding;
  }

  void _register() {
    subLevel.getPlot().addContraption(body);

    final container = SubLevelContainer.of(level);
    if (container is ServerSubLevelContainer) {
      final physics = container.physics;
      if (physics is SubLevelPhysicsSystem) physics.pipeline.addContraption(body);
    }
  }

  /// `setRemoved`: leaves the plot and the pipeline. Idempotent.
  void release() {
    if (_released) return;
    _released = true;

    subLevel.getPlot().removeContraption(body);

    final container = SubLevelContainer.of(level);
    if (container is ServerSubLevelContainer) {
      final physics = container.physics;
      if (physics is SubLevelPhysicsSystem) physics.pipeline.removeContraption(body);
    }
  }

  /// Whether [release] already ran.
  bool get released => _released;

  /// `saveWithoutId`'s passenger pass: moves every non-player passenger into the
  /// contraption's chunk before the entity writes its passengers.
  ///
  /// Players are skipped: a player must not be saved into the plot chunk the
  /// contraption lives in.
  static void gatherPassengersForSave(AbstractContraptionEntity entity) {
    final vec = entity.host.position;
    for (final passenger in entity.host.passengers) {
      if (passenger.isPlayer) continue;
      passenger.teleportTo((vec.$1, vec.$2, vec.$3));
    }
  }
}

/// `AbstractContraptionEntityMixin.moveCollidedEntitiesOnDisassembly`: the two
/// transforms the disassembly applies when the contraption is on a sub-level.
abstract final class ContraptionDisassemblyTransforms {
  /// The local position of a collided entity: project the global position back
  /// into the contraption's space first.
  static Vec3 toLocalVector(
    AbstractContraptionEntity entity,
    Vec3 localVec,
    double partialTicks,
    SubLevel? subLevel,
  ) {
    if (subLevel == null) return entity.toLocalVector(localVec, partialTicks);

    final local = subLevel.logicalPose.transformPositionInverse(
      Vector3d(localVec.$1, localVec.$2, localVec.$3),
    );
    return entity.toLocalVector((local.x, local.y, local.z), partialTicks);
  }

  /// The global position an entity is placed at: project the plot position out
  /// of the sub-level.
  static Vec3 toGlobalPosition(SableLevel level, Vec3 plotPosition) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(plotPosition.$1, plotPosition.$2, plotPosition.$3),
    );
    return (projected.x, projected.y, projected.z);
  }
}

/// `SubLevelPhysicsSystem` of [level], or `null` when it has none.
SubLevelPhysicsSystem? physicsSystemOf(SableLevel level) {
  final container = SubLevelContainer.of(level);
  if (container is! ServerSubLevelContainer) return null;
  final physics = container.physics;
  return physics is SubLevelPhysicsSystem ? physics : null;
}
