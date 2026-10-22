// W6: the Create compatibility layer.
//
// Everything here runs on the Dart VM: the compat layer is written against the
// pure half of the Create port (`create/src/contraptions/**`), and the host-side
// adapters live in `create_host.dart`, which this test does not import.
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/core/structure_transform.dart';
import 'package:create/src/contraptions/entity/contraption_entity.dart';
import 'package:create/src/contraptions/storage/storage_manager.dart' show StorageSync;
import 'package:create/src/core/nbt.dart' show NbtValue;
import 'package:create/src/conveyance/belt/belt_geometry.dart';
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUp(() {
    CreateCompatBlocks.uninstall();
    CreateCompat.install();
  });

  tearDown(() {
    CreateCompat.uninstall();
    ServerLevelPlot.liftProviderLookup = null;
  });

  group('block states', () {
    test('parses a state string into a block key and properties', () {
      final state = parseBlockState('create:white_sail[facing=west,waterlogged=false]');
      expect(state.key, 'create:white_sail');
      expect(state['facing'], 'west');
      expect(state.flag('waterlogged'), isFalse);
    });

    test('a bare block id has no properties', () {
      final state = parseBlockState('minecraft:stone');
      expect(state.key, 'minecraft:stone');
      expect(state.props, isEmpty);
    });

    test('a malformed property list is ignored', () {
      final state = parseBlockState('minecraft:stone[facing');
      expect(state.key, 'minecraft:stone[facing');
      expect(state.props, isEmpty);
    });
  });

  group('sails', () {
    test('every sail is a lift provider', () {
      for (final key in CreateCompatBlocks.sailBlockKeys) {
        final entry = CreateCompatBlocks.liftProviderAt((1, 2, 3), BState(key, const {'facing': 'north'}));
        expect(entry, isNotNull, reason: key);
      }
    });

    test('the normal is the opposite of the facing', () {
      const provider = SailLiftProvider();
      final north = provider.sable$getNormal(const BState('create:white_sail', {'facing': 'north'}));
      expect(north, Direction.south);

      final up = provider.sable$getNormal(const BState('create:sail_frame', {'facing': 'up'}));
      expect(up, Direction.down);
    });

    test('a sail without a facing lifts south (the default facing is north)', () {
      const provider = SailLiftProvider();
      expect(provider.sable$getNormal(const BState('create:white_sail')), Direction.south);
    });

    test('the lift entry carries the step vector of the normal', () {
      final entry = CreateCompatBlocks.liftProviderAt(
        (4, 5, 6),
        const BState('create:orange_sail', {'facing': 'east'}),
      )!;
      expect(entry.normal.x, -1.0);
      expect(entry.normal.y, 0.0);
      expect(entry.normal.z, 0.0);
    });

    test('the centre of mass of a sail is the block centre', () {
      const provider = SailLiftProvider();
      final center = provider.getCenterOfMass(MapBlockGetter(), const BState('create:white_sail'));
      expect(center.x, 0.5);
      expect(center.y, 0.5);
      expect(center.z, 0.5);
    });

    test('the plot lookup answers a lift provider context', () {
      final context = ServerLevelPlot.liftProviderLookup!((0, 0, 0), 'create:red_sail[facing=up]');
      expect(context, isNotNull);
      expect(context!.state, 'create:red_sail[facing=up]');
      expect(context.dir.$2, -1.0);
    });

    test('the plot lookup ignores a non-provider', () {
      expect(ServerLevelPlot.liftProviderLookup!((0, 0, 0), 'minecraft:stone'), isNull);
    });
  });

  group('contraption mass', () {
    test('two blocks weigh two and their centre of mass is between them', () {
      final getter = MapBlockGetter(blocks: {
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
      });

      final tracker = ContraptionMassTracker.build(getter, BoundingBox3i.values(0, 0, 0, 1, 0, 0));
      expect(tracker.isInvalid(), isFalse);
      expect(tracker.mass, 2.0);
      expect(tracker.getInverseMass(), 0.5);

      final center = tracker.getCenterOfMass();
      expect(center.x, closeTo(1.0, 1e-9));
      expect(center.y, closeTo(0.5, 1e-9));
      expect(center.z, closeTo(0.5, 1e-9));
    });

    test('the inertia is the cube term plus the parallel axis term', () {
      final getter = MapBlockGetter(blocks: {
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
      });

      final tracker = ContraptionMassTracker.build(getter, BoundingBox3i.values(0, 0, 0, 1, 0, 0));
      final inertia = tracker.inertiaTensor;

      // Each block: 1/6 on the diagonal; the offset (±0.5, 0, 0) adds 0.25 per
      // block to the y and z diagonals and nothing to x.
      expect(inertia.m00, closeTo(2 / 6, 1e-9));
      expect(inertia.m11, closeTo(2 / 6 + 0.5, 1e-9));
      expect(inertia.m22, closeTo(2 / 6 + 0.5, 1e-9));
      expect(inertia.m01, closeTo(0, 1e-9));
    });

    test('a block with sable:inertia uses it as the principal inertia', () {
      final properties = PhysicsBlockPropertiesTable()
        ..addDefinition(const PhysicsBlockPropertiesDefinition(
          selector: TagOrElementLocation('minecraft:stone'),
          properties: {PhysicsBlockPropertyTypes.inertia: (2.0, 3.0, 4.0)},
        ));

      final getter = MapBlockGetter(blocks: {(0, 0, 0): const BState('minecraft:stone')});
      final tracker = ContraptionMassTracker.build(
        getter,
        BoundingBox3i.values(0, 0, 0, 0, 0, 0),
        properties: properties,
      );

      // A single block sits on the centre of mass, so there is no parallel
      // axis term and the diagonal is exactly the block's own inertia.
      expect(tracker.inertiaTensor.m00, closeTo(2.0, 1e-9));
      expect(tracker.inertiaTensor.m11, closeTo(3.0, 1e-9));
      expect(tracker.inertiaTensor.m22, closeTo(4.0, 1e-9));
    });

    test('an empty contraption has an invalid tracker', () {
      final tracker = ContraptionMassTracker.build(MapBlockGetter(), BoundingBox3i.values(0, 0, 0, 3, 3, 3));
      expect(tracker.isInvalid(), isTrue);
      expect(tracker.getInverseMass(), 0.0);
      expect(() => tracker.getCenterOfMass(), throwsStateError);
    });

    test('a block with a custom centre of mass uses it', () {
      CreateCompatBlocks.registerCenterOfMass([_CustomMass.key], const _CustomMass());

      final getter = MapBlockGetter(
        blocks: {(0, 0, 0): const BState(_CustomMass.key)},
        fullBlocks: const {_CustomMass.key},
      );
      final tracker = ContraptionMassTracker.build(getter, BoundingBox3i.values(0, 0, 0, 0, 0, 0));

      expect(tracker.getCenterOfMass().x, closeTo(0.75, 1e-9));
      expect(tracker.getCenterOfMass().y, closeTo(0.25, 1e-9));
    });
  });

  group('rotation to quaternion', () {
    test('the identity matrix is the identity quaternion', () {
      final q = quaternionFromRotationMatrix(Matrix3d.identity());
      expect(q.x, closeTo(0, 1e-9));
      expect(q.y, closeTo(0, 1e-9));
      expect(q.z, closeTo(0, 1e-9));
      expect(q.w.abs(), closeTo(1, 1e-9));
    });

    test('a 90 degree yaw is a quarter turn around y', () {
      final matrix = Matrix3d.identity()..setFromQuaternion(Quaterniond(0.0, math.sin(math.pi / 4), 0.0, math.cos(math.pi / 4)));
      final q = quaternionFromRotationMatrix(matrix);
      expect(q.y.abs(), closeTo(math.sin(math.pi / 4), 1e-9));
      expect(q.w.abs(), closeTo(math.cos(math.pi / 4), 1e-9));
    });
  });

  group('kinematic contraption', () {
    late Contraption contraption;
    late _TestEntity entity;

    setUp(() {
      contraption = Contraption()
        ..blocks[(0, 0, 0)] = const StructureBlockInfo((0, 0, 0), BState('minecraft:stone'))
        ..blocks[(1, 0, 0)] = const StructureBlockInfo((1, 0, 0), BState('minecraft:stone'));
      entity = _TestEntity(contraption, (10.0, 20.0, 30.0));
    });

    test('the position is the mass centre moved to the anchor', () {
      final body = ContraptionKinematicBody.build(entity)!;
      final position = body.sable$getPosition(1.0);
      expect(position.x, closeTo(11.0, 1e-9));
      expect(position.y, closeTo(20.5, 1e-9));
      expect(position.z, closeTo(30.5, 1e-9));
    });

    test('the position interpolates between the previous and current anchor', () {
      entity
        ..prevAnchor = (10.0, 20.0, 30.0)
        ..currentAnchor = (20.0, 20.0, 30.0);
      final body = ContraptionKinematicBody.build(entity)!;
      expect(body.sable$getPosition(0.5).x, closeTo(16.0, 1e-9));
    });

    test('the local bounds cover the blocks', () {
      final body = ContraptionKinematicBody.build(entity)!;
      final bounds = BoundingBox3i();
      body.sable$getLocalBounds(bounds);
      expect((bounds.minX, bounds.minY, bounds.minZ), (0, 0, 0));
      expect((bounds.maxX, bounds.maxY, bounds.maxZ), (1, 0, 0));
    });

    test('a sail block becomes a lift provider', () {
      contraption.blocks[(2, 0, 0)] = const StructureBlockInfo(
        (2, 0, 0),
        BState('create:white_sail', {'facing': 'north'}),
      );

      final body = ContraptionKinematicBody.build(entity)!;
      expect(body.liftProviders.length, 1);
      expect(body.liftProviders.keys.single, (2, 0, 0));
      expect(body.liftProviders[(2, 0, 0)]!.dir.$3, 1.0);
    });

    test('the orientation is the entity rotation', () {
      final body = ContraptionKinematicBody.build(entity)!;
      final q = body.sable$getOrientation(1.0);
      expect(q.w.abs(), closeTo(1.0, 1e-9));
    });

    test('an empty contraption has no body', () {
      final empty = Contraption();
      expect(ContraptionKinematicBody.build(_TestEntity(empty, (0.0, 0.0, 0.0))), isNull);
    });

    test('the local pose uses the mass centre as the rotation point', () {
      final body = ContraptionKinematicBody.build(entity)!;
      final pose = body.sable$getLocalPose(Pose3d(), 1.0);
      expect(pose.rotationPoint().x, closeTo(1.0, 1e-9));
      expect(pose.position().x, closeTo(11.0, 1e-9));
    });
  });

  group('contraption collider view', () {
    late Contraption contraption;
    late _TestEntity entity;
    late Pose3d pose;

    setUp(() {
      contraption = Contraption()
        ..blocks[(0, 0, 0)] = const StructureBlockInfo((0, 0, 0), BState('minecraft:stone'));
      entity = _TestEntity(contraption, (0.0, 0.0, 0.0));
      pose = Pose3d.full(Vector3d(100.0, 0.0, 0.0), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0));
    });

    test('the anchor is projected out of the sub-level', () {
      final view = SubLevelContraptionView(entity, pose, pose);
      expect(view.getAnchorVec().$1, closeTo(100.0, 1e-9));
    });

    test('the bounding box is projected out of the sub-level', () {
      final view = SubLevelContraptionView(entity, pose, pose);
      expect(view.boundingBox.minX, closeTo(100.0, 1e-9));
      expect(view.boundingBox.maxX, closeTo(102.0, 1e-9));
    });

    test('a world vector is projected back into the plot before it is made local', () {
      final view = SubLevelContraptionView(entity, pose, pose);
      // The contraption's block sits at the plot origin, so its centre in world
      // space is the pose applied to (0.5, 0.5, 0.5).
      final local = view.toLocalVector((100.5, 0.5, 0.5), 0);
      expect(local.$1, closeTo(0.5, 1e-9));
      expect(local.$2, closeTo(0.5, 1e-9));
      expect(local.$3, closeTo(0.5, 1e-9));
    });

    test('the rotation state composes the sub-level orientation', () {
      final yaw = Pose3d.full(
        Vector3d(),
        Quaterniond(0.0, math.sin(math.pi / 4), 0.0, math.cos(math.pi / 4)),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      );
      final view = SubLevelContraptionView(entity, yaw, yaw);
      final matrix = view.getRotationState().asMatrix();

      // A 90 degree yaw maps +x to -z (Minecraft's clockwise yaw).
      expect(matrix.m00, closeTo(0.0, 1e-9));
      expect(matrix.m02.abs(), closeTo(1.0, 1e-9));
    });

    test('the contact point motion includes the sub-level drift', () {
      final later = Pose3d.full(Vector3d(101.0, 0.0, 0.0), Quaterniond(), Vector3d(), Vector3d(1.0, 1.0, 1.0));
      final view = SubLevelContraptionView(entity, later, pose);
      final motion = view.getContactPointMotion((101.0, 0.5, 0.5));
      expect(motion.$1, closeTo(1.0, 1e-9));
    });

    test('colliding without a pose delegates to the plain collider', () {
      // The contraption has no blocks colliders and no entities nearby, so the
      // call is a no-op; the point is that it does not throw.
      expect(() => SubLevelContraptionCollider.collideEntities(entity), returnsNormally);
    });
  });

  group('companion helpers', () {
    late FakeLevel level;
    late ServerSubLevelContainer container;
    late SubLevel ship;

    setUp(() {
      level = FakeLevel();
      container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      ship = container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(100.0, 0.0, 0.0),
          Quaterniond(),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );
    });

    tearDown(() => SubLevelContainer.unregister(level));

    // A position inside a plot is a plot-space position; the pose moves it into
    // the world (here by (100, 0, 0)).
    final plotPos = Vector3d(2560000.0, 0.0, 2560000.0);

    test('runIncludingSubLevels checks the origin itself first', () {
      final found = SubLevelHelper.runIncludingSubLevels<String>(
        level,
        plotPos,
        true,
        ship,
        (candidate, pos) => candidate == ship && pos == (2560000, 0, 2560000) ? 'hit' : null,
      );

      expect(found, 'hit');
      expect(SubLevelHelper.getContainingPos(level, plotPos), same(ship));
    });

    test('runIncludingSubLevels projects the origin out of its sub-level', () {
      final found = SubLevelHelper.runIncludingSubLevels<String>(
        level,
        plotPos,
        false,
        ship,
        (candidate, pos) => candidate == null && pos == (2560100, 0, 2560000) ? 'projected' : null,
      );

      expect(found, 'projected');
    });

    test('distanceSquaredWithSubLevels compares in world space', () {
      // The plot position projects to the ship's world position.
      expect(SubLevelHelper.projectOutOfSubLevel(level, plotPos).x, closeTo(2560100.0, 1e-9));

      // Two plot positions of the same ship stay one block apart.
      expect(
        SubLevelHelper.distanceSquaredWithSubLevels(
          level,
          plotPos,
          Vector3d(2560001.0, 0.0, 2560000.0),
        ),
        closeTo(1, 1e-6),
      );

      // A second ship in the next plot, one hundred blocks away in the world.
      final other = container.allocateNewSubLevel(Pose3d.full(
        Vector3d(),
        Quaterniond(),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      ));
      final otherPlot = Vector3d(
        other.getPlot().plotPos.$1 * 256.0,
        0.0,
        other.getPlot().plotPos.$2 * 256.0,
      );
      final expected = SubLevelHelper.projectOutOfSubLevel(level, plotPos).distanceSquared(
        SubLevelHelper.projectOutOfSubLevel(level, otherPlot),
      );
      expect(
        SubLevelHelper.distanceSquaredWithSubLevels(level, plotPos, otherPlot),
        closeTo(expected, 1e-6),
      );
    });

    test('findIncludingSubLevels answers whether any candidate matches', () {
      expect(
        SubLevelHelper.findIncludingSubLevels(
          level,
          plotPos,
          true,
          ship,
          (candidate, pos) => candidate == ship,
        ),
        isTrue,
      );
      expect(
        SubLevelHelper.findIncludingSubLevels(
          level,
          plotPos,
          true,
          ship,
          (candidate, pos) => false,
        ),
        isFalse,
      );
    });
  });

  group('belt', () {
    test('a horizontal belt pushes along its facing', () {
      final velocity = BeltCollision.velocityFor(
        facing: Direction.east,
        slope: BeltSlope.horizontal,
        beltMovementSpeed: 0.05,
        relativeHitY: 0.75,
      )!;

      // east is +x, and the x axis negates the speed.
      expect(velocity.x, closeTo(-1.0, 1e-9));
      expect(velocity.z, closeTo(0.0, 1e-9));
    });

    test('a body below a horizontal belt is pushed the other way', () {
      final velocity = BeltCollision.velocityFor(
        facing: Direction.south,
        slope: BeltSlope.horizontal,
        beltMovementSpeed: 0.05,
        relativeHitY: 0.25,
      )!;

      expect(velocity.z, closeTo(-1.0, 1e-9));
    });

    test('a sideways belt has no tangent velocity', () {
      expect(
        BeltCollision.velocityFor(
          facing: Direction.east,
          slope: BeltSlope.sideways,
          beltMovementSpeed: 0.05,
          relativeHitY: 0.75,
        ),
        isNull,
      );
    });

    test('the entity height and centre offset are measured in the belt frame', () {
      final pose = Pose3d.full(
        Vector3d(100.0, 0.0, 0.0),
        Quaterniond(),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      );
      expect(BeltMovement.localEntityY(pose, (100.0, 0.25, 0.0)), closeTo(0.25, 1e-9));
      expect(BeltMovement.diffCenter(pose, (0, 0, 0), Axis.z, (100.5, 0.0, 0.0)), closeTo(0.0, 1e-9));
    });
  });

  group('ejector', () {
    test('a flat launch has the capped horizontal speed and no rise', () {
      final impulse = EjectorLaunch.computeLocalImpulse(
        horizontalDistance: 5.0,
        verticalDistance: 0.0,
        gravity: 10.0,
        facing: Direction.north,
      )!;

      expect(impulse.z, closeTo(-3.0, 1e-9));
      expect(impulse.y, closeTo(0.5 * 10.0 * 5.0 / 3.0, 1e-9));
    });

    test('a raised launch reduces the horizontal speed', () {
      final impulse = EjectorLaunch.computeLocalImpulse(
        horizontalDistance: 20.0,
        verticalDistance: 20.0,
        gravity: 10.0,
        facing: Direction.east,
      )!;

      // The horizontal speed is capped at 3 * max(1, px / 10) = 6 m/s.
      expect(impulse.x.abs(), lessThanOrEqualTo(6.0));
      expect(impulse.y, greaterThan(0.0));
    });

    test('no horizontal distance means no launch', () {
      expect(
        EjectorLaunch.computeLocalImpulse(
          horizontalDistance: 0.0,
          verticalDistance: 5.0,
          gravity: 10.0,
          facing: Direction.north,
        ),
        isNull,
      );
    });
  });

  group('saw and crushing wheel', () {
    test('a saw drop is measured across sub-levels', () {
      final level = FakeLevel();
      final container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      final ship = container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(100.0, 0.0, 0.0),
          Quaterniond(),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );

      final saw = Vector3d(2560000.0, 0.0, 2560000.0);
      final cut = Vector3d(2560002.0, 0.0, 2560000.0);
      final delta = SawDrop.itemDeltaMovement(level, saw, cut, ship);

      // Both are in the ship, so the world difference is the plot difference.
      expect(delta.x, closeTo(2.0, 1e-9));
      expect(SawDrop.distanceAcrossSubLevels(level, (2560002.0, 0.0, 2560000.0), (2560000.0, 0.0, 2560000.0)), closeTo(2.0, 1e-9));

      SubLevelContainer.unregister(level);
    });

    test('a crushing wheel pushes along its axis and away from the middle', () {
      final impulse = CrushingWheel.pushImpulse(
        axis: Axis.x,
        speed: 20.0,
        entityLocalPosition: Vector3d(0.0, 1.5, 0.5),
        pos: (0, 0, 0),
        onGround: true,
      )!;

      expect(impulse.z, closeTo(1.0, 1e-9));
      expect(impulse.x, closeTo(0.05, 1e-9));
    });

    test('an entity below the wheel or in the air is not pushed', () {
      expect(
        CrushingWheel.pushImpulse(
          axis: Axis.x,
          speed: 20.0,
          entityLocalPosition: Vector3d(0.0, 1.0, 0.5),
          pos: (0, 0, 0),
          onGround: true,
        ),
        isNull,
      );
      expect(
        CrushingWheel.pushImpulse(
          axis: Axis.x,
          speed: 20.0,
          entityLocalPosition: Vector3d(0.0, 1.5, 0.5),
          pos: (0, 0, 0),
          onGround: false,
        ),
        isNull,
      );
    });
  });

  group('air current', () {
    test('an entity bounding box is projected into the fan frame', () {
      final pose = Pose3d.full(
        Vector3d(100.0, 0.0, 0.0),
        Quaterniond(),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      );
      final local = reverseProjectEntityBounds(const Aabb(100.0, 0.0, 0.0, 101.0, 1.0, 1.0), pose);
      expect(local.minX, closeTo(0.0, 1e-9));
      expect(local.maxX, closeTo(1.0, 1e-9));
    });

    test('an entity position is projected into the fan frame', () {
      final pose = Pose3d.full(
        Vector3d(100.0, 0.0, 0.0),
        Quaterniond(),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      );
      final local = reverseProjectPosition((102.0, 3.0, 4.0), pose);
      expect(local.$1, closeTo(2.0, 1e-9));
      expect(local.$2, closeTo(3.0, 1e-9));
    });

    test('the flow vector is rotated out of the fan frame', () {
      final pose = Pose3d.full(
        Vector3d(),
        Quaterniond(0.0, math.sin(math.pi / 4), 0.0, math.cos(math.pi / 4)),
        Vector3d(),
        Vector3d(1.0, 1.0, 1.0),
      );

      final motion = transformFlowVector((1, 0, 0), 0.5, (0.0, 0.0, 0.0), 10.0, pose);
      // A 90 degree yaw maps local +x to world -z; the flow is clamped to the
      // max acceleration and scaled by 0.125.
      expect(motion.$1.abs(), lessThan(1e-9));
      expect(motion.$3.abs(), closeTo(0.0625, 1e-9));
    });
  });

  group('range checks', () {
    test('two blocks in different sub-levels are compared in world space', () {
      final level = FakeLevel();
      final container = ServerSubLevelContainer(
        level,
        FakeChunkHost(level),
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      container.allocateNewSubLevel(
        Pose3d.full(
          Vector3d(100.0, 0.0, 0.0),
          Quaterniond(),
          Vector3d(),
          Vector3d(1.0, 1.0, 1.0),
        ),
      );

      final plot = Vector3d(2560000.0, 0.0, 2560000.0);
      expect(CreateRangeChecks.linksWithinRange(level, plot, plot, 1), isTrue);

      // Three blocks apart in the plot is three blocks apart in the world.
      final nearby = Vector3d(2560003.0, 0.0, 2560000.0);
      expect(CreateRangeChecks.linksWithinRange(level, plot, nearby, 4), isTrue);
      expect(CreateRangeChecks.linksWithinRange(level, plot, nearby, 1), isFalse);

      SubLevelContainer.unregister(level);
    });
  });

  group('assembly listeners', () {
    test('a chain conveyor listener is registered', () {
      expect(CreateCompatBlocks.assemblyListenerOf(const BState('create:chain_conveyor')), isNotNull);
    });

    test('the sail keys are the frame, the white sail and the sixteen dyed sails', () {
      // The frame plus the sixteen dyed sails; the white sail is one of them.
      expect(CreateCompatBlocks.sailBlockKeys.length, 17);
      expect(CreateCompatBlocks.sailBlockKeys, contains('create:sail_frame'));
      expect(CreateCompatBlocks.sailBlockKeys, contains('create:white_sail'));
      expect(CreateCompatBlocks.sailBlockKeys, contains('create:black_sail'));
    });
  });
}

final class _CustomMass implements BlockSubLevelCustomCenterOfMass {
  static const String key = 'test:custom_mass';

  const _CustomMass();

  @override
  Vector3d getCenterOfMass(BlockGetter blockGetter, BState state) => Vector3d(0.75, 0.25, 0.5);
}

/// A contraption entity with no world: enough for the bridge, which reads only
/// the contraption and the entity transforms.
final class _TestEntity extends AbstractContraptionEntity {
  _TestEntity(Contraption contraption, Vec3 anchor) : _anchor = anchor, super(_TestHost(anchor)) {
    setContraption(contraption);
    prevPosInvalid = false;
  }

  final Vec3 _anchor;
  Vec3? prevAnchor;
  Vec3? currentAnchor;

  Vec3 get _current => currentAnchor ?? _anchor;

  Vec3 get _previous => prevAnchor ?? _current;

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  Vec3 getAnchorVec() => _current;

  @override
  Vec3 getPrevAnchorVec() => _previous;

  @override
  Vec3 getPrevPositionVec() => _previous;

  @override
  ContraptionRotationState getRotationState() => ContraptionRotationState();

  @override
  Future<void> tickContraption() async {}

  @override
  StructureTransform makeStructureTransform() => throw UnimplementedError();

  @override
  double getStalledAngle() => 0;

  @override
  void handleStallInformation(double x, double y, double z, double angle) {}
}

final class _TestHost implements ContraptionEntityHost {
  _TestHost(this._position);

  Vec3 _position;

  @override
  void setSyncedEntry(int index, List<int> data) {}

  @override
  int get entityId => 1;

  @override
  String get uuid => '00000000-0000-0000-0000-000000000001';

  @override
  bool get isAlive => true;

  @override
  bool get isRemoved => false;

  @override
  bool get stalled => false;

  @override
  Vec3 get position => _position;

  @override
  Vec3 get prevPosition => _position;

  @override
  Aabb get boundingBox => Aabb(_position.$1, _position.$2, _position.$3, _position.$1 + 2, _position.$2 + 1, _position.$3 + 1);

  @override
  void setBoundingBox(Aabb box) {}

  @override
  Vec3 get deltaMovement => vec3Zero;

  @override
  void setDeltaMovement(Vec3 motion) {}

  @override
  void setPosition(Vec3 position) => _position = position;

  @override
  void teleport(Vec3 position) => _position = position;

  @override
  List<ContraptionPassengerRef> get passengers => const [];

  @override
  bool hasPassenger(ContraptionPassengerRef passenger) => false;

  @override
  void addPassenger(ContraptionPassengerRef passenger, {bool force = true}) {}

  @override
  void removePassenger(ContraptionPassengerRef passenger) {}

  @override
  void ejectPassengers() {}

  @override
  void setPassengerPosition(ContraptionPassengerRef passenger, Vec3 position) {}

  @override
  void teleportEntity(ContraptionPassengerRef passenger, Vec3 position) {}

  @override
  Object? get vehicle => null;

  @override
  ContraptionPassengerRef? get vehiclePassenger => null;

  @override
  Vec3 get vehiclePosition => vec3Zero;

  @override
  Vec3 get vehiclePrevPosition => vec3Zero;

  @override
  Vec3 get vehicleDeltaMovement => vec3Zero;

  @override
  bool get vehicleIsMinecart => false;

  @override
  void setVehicleDeltaMovement(Vec3 motion) {}

  @override
  Object? controllerAt(Pos pos) => null;

  @override
  void setRotation(double yaw, double pitch) {}

  @override
  void setOnGround(bool onGround) {}

  @override
  double get maxUpStep => 0.6;

  @override
  void playSound(String sound, Vec3 at, {double volume = 1, double pitch = 1}) {}

  @override
  void sendPayload(String channel, Map<String, Object?> fields) {}

  @override
  void setStalled(bool stalled) {}

  @override
  String? get controllingPlayer => null;

  @override
  void setControllingPlayer(String? uuid) {}

  @override
  NbtValue? getPersistentData(String key) => null;

  @override
  void setPersistentData(String key, NbtValue? value) {}

  @override
  ContraptionLevel get level => throw UnimplementedError();

  @override
  ContraptionCollisionEntity? collisionEntityById(int id) => null;

  @override
  void sendBlockChanged(Pos localPos, BState state) {}

  @override
  void sendStorageSync(StorageSync sync) {}

  @override
  void sendSeatMapping(Map<String, int> mapping, {int? dismountedId}) {}

  @override
  void sendStall(double angle) {}

  @override
  void sendControlsAbort(String playerUuid) {}

  @override
  void sendDisassembly(StructureTransform transform) {}

  @override
  List<ContraptionCollisionEntity> entitiesNear(Aabb box) => const [];

  @override
  ContraptionPassengerRef? passengerFromHost(Object handle) => null;

  @override
  void remove() {}
}
