// The pure half of `sable_jolt`: the block model the voxel world is built from
// and the buoyancy port. No module, no host: this is what runs on the VM.
import 'package:sable/sable.dart';
import 'package:sable_jolt/sable_jolt.dart';
import 'package:test/test.dart';

void main() {
  group('packed block states', () {
    test('round trip the collider index and the voxel state', () {
      final packed = packBlockState(3, VoxelPhysicsState.corner);
      expect(colliderIndexOfPacked(packed), 3);
      expect(voxelStateOfPacked(packed), VoxelPhysicsState.corner);
    });

    test('no collider packs as -1', () {
      final packed = packBlockState(-1, VoxelPhysicsState.empty);
      expect(colliderIndexOfPacked(packed), -1);
      expect(packed, VoxelPhysicsState.empty);
    });

    test('interior and empty blocks are never solid', () {
      final colliders = BlockColliderRegistry()..add(const BlockColliderData());
      expect(
        isSolidBlock(packBlockState(0, VoxelPhysicsState.face), colliders),
        isTrue,
      );
      expect(
        isSolidBlock(packBlockState(0, VoxelPhysicsState.interior), colliders),
        isFalse,
      );
      expect(
        isSolidBlock(packBlockState(0, VoxelPhysicsState.empty), colliders),
        isFalse,
      );
      expect(isSolidBlock(packBlockState(-1, VoxelPhysicsState.face), colliders), isFalse);
    });

    test('a collider without boxes is not solid', () {
      final colliders = BlockColliderRegistry()
        ..add(const BlockColliderData(boxes: []));
      expect(
        isSolidBlock(packBlockState(0, VoxelPhysicsState.face), colliders),
        isFalse,
      );
    });
  });

  group('block section store', () {
    test('stores, reads and removes sections', () {
      final store = BlockSectionStore();
      final states = List<int>.filled(4096, 0);
      states[1 + (2 << 4) + (3 << 8)] = 42;
      store.setSection(0, 0, 0, states);

      expect(store.blockAt(1, 3, 2), 42);
      expect(store.blockAt(0, 0, 0), 0);
      // A block outside the loaded sections reads as air.
      expect(store.blockAt(16, 0, 0), 0);

      store.setBlock(1, 3, 2, 7);
      expect(store.blockAt(1, 3, 2), 7);

      store.removeSection(0, 0, 0);
      expect(store.blockAt(1, 3, 2), 0);
    });

    test('rejects a section that is not 4096 blocks', () {
      expect(
        () => BlockSectionStore().setSection(0, 0, 0, const [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('enumerates solid blocks with absolute coordinates', () {
      final colliders = BlockColliderRegistry()..add(const BlockColliderData());
      final store = BlockSectionStore();
      final states = List<int>.filled(4096, 0);
      states[0 + (0 << 4) + (0 << 8)] =
          packBlockState(0, VoxelPhysicsState.face);
      states[2 + (1 << 4) + (1 << 8)] =
          packBlockState(0, VoxelPhysicsState.interior);
      store.setSection(2, -1, 3, states);

      expect(store.solidBlocks(colliders), [
        ((32, -16, 48), packBlockState(0, VoxelPhysicsState.face)),
      ]);
    });
  });

  group('buoyancy', () {
    late BlockColliderRegistry colliders;
    late BlockSectionStore world;
    // The sub-level's own block: collider index 1, buoyancy volume 0.5.
    late int bodyBlock;

    setUp(() {
      colliders = BlockColliderRegistry()
        ..add(const BlockColliderData(fluid: true, volume: 0.0))
        ..add(const BlockColliderData(volume: 0.5));
      bodyBlock = packBlockState(1, VoxelPhysicsState.face);
      world = BlockSectionStore();
    });

    test('a body block overlapping a fluid gets lift from its own volume', () {
      // The world is one fluid block at (0, 0, 0).
      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      // Bounds whose extent sum is >= 10: `buoyancy.rs:69` then samples the
      // block once, at its center, with a half-extent of 0.5.
      final pose = Pose3d()..position().set(0.5, 0.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), bodyBlock)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(),
      );

      expect(forces, hasLength(1));
      // `10.5 * overlapVolume * bodyVolume` (`buoyancy.rs:187-189`): the unit
      // block overlaps the unit fluid block completely.
      expect(forces.single.force.y, closeTo(10.5 * 0.5, 1e-9));
      expect(forces.single.force.x, 0.0);
      // The sample point is the block center in world space
      // (`body.position().transform_point(local)`, `buoyancy.rs:139-140`).
      expect(forces.single.point.y, closeTo(0.5, 1e-9));
    });

    test('drag opposes the velocity at the sample point', () {
      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      final pose = Pose3d()..position().set(0.5, 0.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), bodyBlock)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(1.0, 0.0, 0.0),
      );

      // `-velo * 1.7 * volume` (`buoyancy.rs:150-152`).
      expect(forces.single.force.x, closeTo(-1.7, 1e-9));
      expect(forces.single.force.y, closeTo(10.5 * 0.5, 1e-9));
    });

    test('nothing overlaps when the body is above the fluid', () {
      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      final pose = Pose3d()..position().set(0.5, 10.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), bodyBlock)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(),
      );
      expect(forces, isEmpty);
    });

    test('a small body is sampled at eight sub-points', () {
      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      final pose = Pose3d()..position().set(0.5, 0.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        // An extent sum below 10 takes the eight-sample path
        // (`buoyancy.rs:69-101`).
        localBounds: BoundingBox3i.values(0, 0, 0, 0, 0, 0),
        bodyBlocks: [((0, 0, 0), bodyBlock)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(),
      );
      // Each of the eight sub-points overlaps an eighth of the fluid block, so
      // the total lift is the same as the single-sample case.
      expect(forces, hasLength(8));
      final total = forces.fold<double>(0.0, (sum, f) => sum + f.force.y);
      expect(total, closeTo(10.5 * 0.5, 1e-9));
      for (final force in forces) {
        expect(force.point.y, anyOf(closeTo(0.25, 1e-9), closeTo(0.75, 1e-9)));
      }
    });

    test('drag strength is the constant 1.0 and lift uses the collider volume', () {
      // `do_drag(body, &vels, static_pos, &local_pos, size, 1.0)`
      // (`buoyancy.rs:88`) versus
      // `do_float(body, static_pos, &local_pos, size, voxel_collider_data.volume)`
      // (`buoyancy.rs:135`): the drag strength is always 1.0, and only the lift
      // is scaled by the sub-level block's own collider volume.
      colliders.add(const BlockColliderData(volume: 0.25));
      final quarter = packBlockState(2, VoxelPhysicsState.face);

      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      final pose = Pose3d()..position().set(0.5, 0.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), quarter)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(1.0, 0.0, 0.0),
      );

      expect(forces, hasLength(1));
      // `-velo * 1.7 * overlap * 1.0` — the same drag the 0.5-volume block gets.
      expect(forces.single.force.x, closeTo(-1.7, 1e-9));
      // `10.5 * overlap * volume`, with volume = 0.25.
      expect(forces.single.force.y, closeTo(10.5 * 0.25, 1e-9));
    });

    test('a block with the default collider volume still drags', () {
      // The default `BlockColliderData.volume` is 0.0 (`voxel.dart:75`). The
      // Rust never passes it to `do_drag` (`buoyancy.rs:63,88` pass `1.0`), so
      // such a block still gets drag, just no lift.
      colliders.add(const BlockColliderData());
      final noVolume = packBlockState(2, VoxelPhysicsState.face);

      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      final pose = Pose3d()..position().set(0.5, 0.5, 0.5);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), noVolume)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(1.0, 0.0, 0.0),
      );

      expect(forces, hasLength(1));
      expect(forces.single.force.x, closeTo(-1.7, 1e-9));
      expect(forces.single.force.y, 0.0);
      expect(dragStrength, 1.0);
    });

    test('a rotated body transforms its sample points but not the lift axis', () {
      final states = List<int>.filled(4096, 0);
      states[0] = packBlockState(0, VoxelPhysicsState.face);
      world.setSection(0, 0, 0, states);

      // 90 degrees about X: the block's local +Y maps to world +Z.
      final pose = Pose3d()
        ..position().set(0.5, 0.5, 0.5)
        ..orientation().set(0.7071067811865476, 0.0, 0.0, 0.7071067811865476);
      final forces = computeBuoyancy(
        pose: pose,
        centerOfMass: Vector3d(0.5, 0.5, 0.5),
        localBounds: BoundingBox3i.values(-8, -8, -8, 8, 8, 8),
        bodyBlocks: [((0, 0, 0), bodyBlock)],
        colliders: colliders,
        world: StoreBlockSource(world),
        velocityAt: (_) => Vector3d(),
      );
      expect(forces, isNotEmpty);
      // Lift is always +Y, wherever the body is rotated.
      final total = forces.fold<double>(0.0, (sum, f) => sum + f.force.y);
      expect(total, closeTo(10.5 * 0.5, 1e-9));
      // The sample point is the rotated center, still (0.5, 0.5, 0.5) here.
      expect(forces.single.point.x, closeTo(0.5, 1e-9));
      expect(forces.single.point.z, closeTo(0.5, 1e-9));
    });
  });
}
