// The floating-block model: cluster statistics, material NBT and the cluster
// container's block bookkeeping.
//
// Java: `sable/common/.../physics/floating_block/{FloatingBlockData,
// FloatingBlockMaterial,FloatingBlockController,FloatingClusterContainer}.java`.
//
// The controller's lift/friction behaviour is covered by
// `physics_forces_test.dart`; this file covers the state machines underneath
// it: what a cluster accumulates, how a removal reverses an addition, how the
// pressure sample is placed in the world, and how blocks move between clusters.
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketException;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Body implements FloatingBlockBody {
  @override
  Vector3d centerOfMass = Vector3d();

  @override
  double mass = 100;

  @override
  Matrix3d inverseInertiaTensor = Matrix3d();

  /// state -> material; absent states have no material.
  final Map<String, FloatingBlockMaterial> materials = {
    'sable:floater': const FloatingBlockMaterial(liftStrength: 2.0),
    'sable:other': const FloatingBlockMaterial(liftStrength: 5.0),
  };

  /// state -> floating scale.
  final Map<String, double> scales = {'sable:floater': 2.0, 'sable:other': 3.0};

  @override
  FloatingBlockMaterial? materialOf(String state) => materials[state];

  @override
  double floatingScaleOf(String state) => scales[state] ?? 1.0;

  @override
  double pressureAt(Vector3d worldPosition) => worldPosition.x + worldPosition.y + worldPosition.z;
}

SubLevel makeSubLevel(FakeLevel level, FakeChunkHost host) {
  final container = TestContainer(level, host);
  SubLevelContainer.register(container);
  return container.allocateSubLevel('00000000-0000-0000-0000-000000000001', 0, 0, Pose3d());
}

void main() {
  setUp(() {
    SubLevelContainer.clearAll();
    FloatingBlockMaterialDataHandler.clear();
  });

  group('FloatingBlockData', () {
    test('one block sets the scale, the weighted position and the cube inertia', () {
      final data = FloatingBlockData()..addFloatingBlock(Vector3d(1, 0, 0), 2.0);

      expect(data.blockCount, 1);
      expect(data.totalScale, 2.0);
      expect(data.weightedPosition, Vector3d(2, 0, 0));
      expect(data.centerOfCluster(), Vector3d(1, 0, 0));

      // `outerProduct` is Σ scale·pos·posᵀ + I·scale/6. A single block at
      // (1,0,0) with scale 2 contributes 2·(1,0,0)ᵀ(1,0,0) — but the
      // off-diagonal term of `addData` is only added from the *second* block
      // on (`FloatingBlockData.java:29-35`), so the first block contributes
      // only the cube term.
      expect(data.outerProduct.m00, closeTo(2.0 / 6.0, 1e-12));
      expect(data.outerProduct.m11, closeTo(2.0 / 6.0, 1e-12));
      expect(data.outerProduct.m22, closeTo(2.0 / 6.0, 1e-12));
      expect(data.outerProduct.m01, 0.0);
    });

    test('a second block adds the offset outer product and moves the centre', () {
      final data = FloatingBlockData()
        ..addFloatingBlock(Vector3d(1, 0, 0), 1.0)
        ..addFloatingBlock(Vector3d(3, 0, 0), 1.0);

      expect(data.blockCount, 2);
      expect(data.totalScale, 2.0);
      expect(data.weightedPosition, Vector3d(4, 0, 0));
      expect(data.centerOfCluster(), Vector3d(2, 0, 0));

      // First block: I/6. Second: 2·u·uᵀ with u = (3,0,0) − (2,0,0), then I/6.
      expect(data.outerProduct.m00, closeTo(1.0 / 6.0 + 2.0 + 1.0 / 6.0, 1e-12));
      expect(data.outerProduct.m11, closeTo(2.0 / 6.0, 1e-12));
      expect(data.outerProduct.m22, closeTo(2.0 / 6.0, 1e-12));
    });

    test('removing the second block restores the first block exactly', () {
      final data = FloatingBlockData()
        ..addFloatingBlock(Vector3d(1, 0, 0), 1.0)
        ..addFloatingBlock(Vector3d(3, 0, 0), 1.0)
        ..removeFloatingBlock(Vector3d(3, 0, 0), 1.0);

      expect(data.blockCount, 1);
      expect(data.totalScale, 1.0);
      expect(data.weightedPosition, Vector3d(1, 0, 0));
      expect(data.outerProduct.m00, closeTo(1.0 / 6.0, 1e-12));
      expect(data.outerProduct.m11, closeTo(1.0 / 6.0, 1e-12));
      expect(data.outerProduct.m22, closeTo(1.0 / 6.0, 1e-12));
    });

    test('translateOrigin moves the weighted position by scale·nudge', () {
      final data = FloatingBlockData()..addFloatingBlock(Vector3d(1, 0, 0), 2.0);
      data.translateOrigin(Vector3d(0.5, -1, 2));
      expect(data.weightedPosition, Vector3d(3, -2, 4));
    });

    test('averagePositionMatrix divides the outer product by the total scale', () {
      final data = FloatingBlockData()..addFloatingBlock(Vector3d(0, 0, 0), 3.0);
      final average = data.averagePositionMatrix();
      expect(average.m00, closeTo(3.0 / 6.0 / 3.0, 1e-12));
    });

    test('computePressureScale samples pose.position + R·weightedPosition/scale', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final subLevel = makeSubLevel(level, host);
      subLevel.pose.position().set(10, 20, 30);

      final data = FloatingBlockData()..addFloatingBlock(Vector3d(1, 0, 0), 1.0);
      final sampled = <Vector3d>[];
      data.computePressureScale(subLevel, (world) {
        sampled.add(Vector3d.copy(world));
        return 7.0;
      });

      expect(sampled.single, Vector3d(11, 20, 30));
      expect(data.getPressureScale(), 7.0);
    });

    test('computePressureScale never mutates the sub-level pose', () {
      // Regression: the first port wrote the world centre back into the pose's
      // position vector (`SubLevel.logicalPose().position()` is mutable), so
      // sampling pressure moved the sub-level.
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final subLevel = makeSubLevel(level, host);
      subLevel.pose.position().set(10, 20, 30);

      final data = FloatingBlockData()..addFloatingBlock(Vector3d(4, 0, 0), 2.0);
      data.computePressureScale(subLevel, (_) => 1.0);

      expect(subLevel.logicalPose.position(), Vector3d(10, 20, 30));
    });

    test('a rotated pose rotates the cluster centre before translating it', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final subLevel = makeSubLevel(level, host);
      subLevel.pose.position().set(0, 0, 0);
      subLevel.pose.orientation().fromAxisAngleDeg(Vector3d(0, 1, 0), 90);

      final data = FloatingBlockData()..addFloatingBlock(Vector3d(1, 0, 0), 1.0);
      Vector3d? sampled;
      data.computePressureScale(subLevel, (world) {
        sampled = Vector3d.copy(world);
        return 1.0;
      });

      // A +90° turn about Y maps +X onto −Z.
      expect(sampled!.x, closeTo(0, 1e-12));
      expect(sampled!.z, closeTo(-1, 1e-12));
    });
  });

  group('FloatingClusterContainer', () {
    test('blocks of one material share a cluster; another material gets its own', () {
      final body = _Body();
      final container = FloatingClusterContainer(body)
        ..addFloatingBlock('sable:floater', Vector3d(0, 0, 0))
        ..addFloatingBlock('sable:floater', Vector3d(1, 0, 0))
        ..addFloatingBlock('sable:other', Vector3d(0, 0, 0));

      expect(container.clusters, hasLength(2));
      expect(container.blockCount, 3);
      expect(container.clusters.first.getMaterial().liftStrength, 2.0);
      expect(container.clusters.first.getBlockData().blockCount, 2);
      expect(container.clusters.last.getBlockData().blockCount, 1);
    });

    test('a block without a material is ignored', () {
      final container = FloatingClusterContainer(_Body())
        ..addFloatingBlock('minecraft:stone', Vector3d(0, 0, 0));
      expect(container.clusters, isEmpty);
      expect(container.blockCount, 0);
    });

    test('removing the last block of a cluster removes the cluster', () {
      final body = _Body();
      final container = FloatingClusterContainer(body)
        ..addFloatingBlock('sable:floater', Vector3d(0, 0, 0))
        ..removeFloatingBlock('sable:floater', Vector3d(0, 0, 0));
      expect(container.clusters, isEmpty);
    });

    test('queued changes are applied around the centre of mass and then cleared', () {
      final body = _Body()..centerOfMass = Vector3d(10, 0, 0);
      final container = FloatingClusterContainer(body)
        ..queueAddFloatingBlock('sable:floater', (10, 0, 0))
        ..queueAddFloatingBlock('sable:other', (12, 0, 0));

      expect(container.needsTicking(), isTrue);
      container.processBlockChanges(body.centerOfMass);

      expect(container.addedBlocks, isEmpty);
      expect(container.removedBlocks, isEmpty);
      expect(container.blockCount, 2);
      // Block (10,0,0) is at local (0.5, 0.5, 0.5) minus the centre of mass.
      final floater = container.clusters.firstWhere((c) => c.getMaterial().liftStrength == 2.0);
      expect(floater.getBlockData().weightedPosition.x, closeTo(2.0 * (10.5 - 10), 1e-12));
    });

    test('a queued removal is applied before the queued addition of the same block', () {
      final body = _Body();
      final container = FloatingClusterContainer(body)
        ..addFloatingBlock('sable:floater', Vector3d(0.5, 0.5, 0.5))
        ..queueRemoveFloatingBlock('sable:floater', (0, 0, 0))
        ..queueAddFloatingBlock('sable:floater', (0, 0, 0));

      container.processBlockChanges(Vector3d());

      expect(container.blockCount, 1);
      expect(container.clusters.single.getBlockData().weightedPosition, Vector3d(1, 1, 1));
    });

    test('needsTicking is true for queued changes even with no clusters', () {
      final container = FloatingClusterContainer(_Body());
      expect(container.needsTicking(), isFalse);
      container.queueAddFloatingBlock('sable:floater', (0, 0, 0));
      expect(container.needsTicking(), isTrue);
    });
  });

  group('FloatingBlockMaterial', () {
    test('the NBT form omits every default', () {
      const material = FloatingBlockMaterial(liftStrength: 2.0);
      expect(material.toNbt().keys, ['lift_strength']);
    });

    test('the NBT form writes every non-default field with the Java key', () {
      const material = FloatingBlockMaterial(
        liftStrength: 2.0,
        preventSelfLift: true,
        scaleWithPressure: true,
        scaleWithGravity: true,
        transitionSpeed: 0.5,
        slowVerticalFriction: 1.0,
        fastVerticalFriction: 2.0,
        slowHorizontalFriction: 3.0,
        fastHorizontalFriction: 4.0,
      );
      final nbt = material.toNbt();
      expect(nbt.keys, containsAll([
        'lift_strength',
        'prevent_self_lift',
        'scale_with_pressure',
        'scale_friction_with_gravity',
        'transition_speed',
        'slow_vertical_friction',
        'fast_vertical_friction',
        'slow_horizontal_friction',
        'fast_horizontal_friction',
      ]));
      expect(FloatingBlockMaterial.fromNbt(nbt), material);
    });

    test('a missing lift_strength is rejected, as the required codec field is', () {
      expect(() => FloatingBlockMaterial.fromNbt(const {}), throwsA(isA<PacketException>()));
    });

    test('the payload body round trips through network NBT', () {
      const material = FloatingBlockMaterial(
        liftStrength: 1.5,
        scaleWithPressure: true,
        slowHorizontalFriction: 0.25,
      );
      final bytes = NetworkNbtMap.encode(material.toNbt());
      expect(FloatingBlockMaterial.fromNbt(NetworkNbtMap.decode(bytes)), material);
    });

    test('equality covers every field', () {
      const a = FloatingBlockMaterial(liftStrength: 1.0);
      const b = FloatingBlockMaterial(liftStrength: 1.0);
      const c = FloatingBlockMaterial(liftStrength: 1.0, transitionSpeed: 0.1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.copyWith(transitionSpeed: 0.1), c);
    });

    test('the data handler looks materials up by id and clears', () {
      FloatingBlockMaterialDataHandler.addMaterial(
        'sable:air',
        const FloatingBlockMaterial(liftStrength: 1.0),
      );
      FloatingBlockMaterialDataHandler.addMaterial(
        'sable:steam',
        const FloatingBlockMaterial(liftStrength: 2.0),
      );
      expect(FloatingBlockMaterialDataHandler.material('sable:steam')!.liftStrength, 2.0);
      expect(FloatingBlockMaterialDataHandler.material('sable:missing'), isNull);
      FloatingBlockMaterialDataHandler.clear();
      expect(FloatingBlockMaterialDataHandler.material('sable:air'), isNull);
    });
  });

  group('FloatingBlockController block bookkeeping', () {
    test('processBlockChanges nudges the clusters by the centre-of-mass delta', () {
      final body = _Body()..centerOfMass = Vector3d(0, 0, 0);
      final controller = FloatingBlockController(body);
      controller.addFloatingBlock('sable:floater', Vector3d(1, 0, 0));

      // First call: previous centre is (0,0,0), the nudge is zero.
      controller.processBlockChanges();
      expect(controller.sublevelContainer.clusters.single.getBlockData().weightedPosition, Vector3d(2, 0, 0));

      // The centre moves by +1 on X: the stored local positions shift by −1.
      body.centerOfMass = Vector3d(1, 0, 0);
      controller.processBlockChanges();
      expect(controller.sublevelContainer.clusters.single.getBlockData().weightedPosition, Vector3d(0, 0, 0));
    });

    test('queueAddFloatingBlock goes through the sub-level container', () {
      final body = _Body();
      final controller = FloatingBlockController(body)
        ..queueAddFloatingBlock('sable:floater', (2, 3, 4));
      expect(controller.sublevelContainer.addedBlocks, {(2, 3, 4): 'sable:floater'});
    });

    test('needsTicking sees the sub-level container and contraption containers', () {
      final body = _Body();
      final controller = FloatingBlockController(body);
      expect(controller.needsTicking(), isFalse);
      final contraption = FloatingClusterContainer(body)..queueAddFloatingBlock('sable:floater', (0, 0, 0));
      controller.physicsTick(
        0,
        1 / 20,
        Vector3d(),
        Vector3d(),
        Vector3d(),
        Vector3d(),
        gravity: Vector3d(0, -9.81, 0),
        contraptionContainers: [contraption],
      );
      // Java's `processBlockChanges` only drains the sub-level container; a
      // contraption drains its own queue (`FloatingBlockController.java:154-163`).
      expect(controller.containers, contains(contraption));
      expect(contraption.addedBlocks, hasLength(1));
    });
  });
}