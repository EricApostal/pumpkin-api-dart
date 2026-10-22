// The physics boundary: the pipeline contract, the provider registry and the
// no-op fallback pipeline.
//
// Everything here is pure (it loads on the plain Dart VM), and the assertions
// are the ones the Java classes make:
//
//  * `PhysicsPipelineProvider.INSTANCE` picks the highest `@LoadPriority`, and
//    `StaticPhysicsPipelineProvider` is the 900 fallback;
//  * `StaticPhysicsPipeline` moves nothing, reads the sub-level's logical pose
//    and teleports by writing that pose.
//
// Java: `sable/common/.../api/physics/PhysicsPipelineProvider.java`,
// `sable/common/.../physics/impl/none/StaticPhysicsPipeline{Provider}.java`.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A server sub-level for the pipeline tests: needs a registered container and
/// nothing else.
ServerSubLevel makeSubLevel(FakeLevel level, FakeChunkHost host, String uuid) {
  SubLevelContainer.register(
    ServerSubLevelContainer(
      level,
      host,
      3,
      4,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
    ),
  );
  final container = SubLevelContainer.of(level)! as ServerSubLevelContainer;
  return container.allocateSubLevel(uuid, 0, 0, Pose3d()) as ServerSubLevel;
}

/// A provider that records how it was called.
final class RecordingProvider implements PhysicsPipelineProvider {
  @override
  final int loadPriority;
  final List<String> calls = [];
  final StaticPhysicsPipeline pipeline;

  RecordingProvider(this.loadPriority, [StaticPhysicsPipeline? pipeline])
    : pipeline = pipeline ?? StaticPhysicsPipeline();

  @override
  PhysicsPipeline createPipeline(SableLevel level) {
    calls.add(level.dimensionId);
    return pipeline;
  }
}

void main() {
  setUp(() {
    SubLevelContainer.clearAll();
    PhysicsPipelineProviders.clear();
  });

  group('PhysicsPipelineProviders', () {
    test('resolving with nothing registered throws', () {
      expect(PhysicsPipelineProviders.resolve, throwsStateError);
      expect(() => PhysicsPipelineProviders.createPipeline(FakeLevel()), throwsStateError);
    });

    test('the highest priority wins, whatever the registration order', () {
      final low = RecordingProvider(100);
      final high = RecordingProvider(2000);
      PhysicsPipelineProviders.register(high);
      PhysicsPipelineProviders.register(low);
      expect(PhysicsPipelineProviders.resolve(), same(high));

      PhysicsPipelineProviders.clear();
      PhysicsPipelineProviders.register(low);
      PhysicsPipelineProviders.register(high);
      expect(PhysicsPipelineProviders.resolve(), same(high));
    });

    test('equal priorities keep the first registration (Java Stream.max)', () {
      final first = RecordingProvider(1000);
      final second = RecordingProvider(1000);
      PhysicsPipelineProviders.register(first);
      PhysicsPipelineProviders.register(second);
      expect(PhysicsPipelineProviders.resolve(), same(first));
    });

    test('the default priority is the Java annotation default, 1000', () {
      expect(StaticPhysicsPipelineProvider().loadPriority, 900);
      expect(RecordingProvider(1000).loadPriority, 1000);
    });

    test('registering the same provider twice is a no-op', () {
      final provider = RecordingProvider(1000);
      PhysicsPipelineProviders.register(provider);
      PhysicsPipelineProviders.register(provider);
      expect(PhysicsPipelineProviders.registered, hasLength(1));
      PhysicsPipelineProviders.unregister(provider);
      expect(PhysicsPipelineProviders.registered, isEmpty);
    });

    test('createPipeline delegates to the resolved provider with the level', () {
      final provider = RecordingProvider(1000);
      PhysicsPipelineProviders.register(provider);
      final level = FakeLevel('minecraft:the_end');
      PhysicsPipelineProviders.createPipeline(level);
      expect(provider.calls, ['minecraft:the_end']);
    });

    test('the static provider is only picked when nothing better is registered', () {
      PhysicsPipelineProviders.register(const StaticPhysicsPipelineProvider());
      final real = RecordingProvider(1000);
      PhysicsPipelineProviders.register(real);
      expect(PhysicsPipelineProviders.resolve(), same(real));

      PhysicsPipelineProviders.unregister(real);
      expect(PhysicsPipelineProviders.resolve(), isA<StaticPhysicsPipelineProvider>());
    });
  });

  group('StaticPhysicsPipeline', () {
    test('addSubLevel returns one handle per sub-level, and remove forgets it', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      final handle = pipeline.addSubLevel(subLevel, Pose3d());
      expect(handle, isA<StaticBodyHandle>());
      expect(pipeline.addSubLevel(subLevel, Pose3d()), same(handle));
      expect(handle.isValid, isTrue);
      pipeline.removeSubLevel(subLevel);
      expect(pipeline.bodies, isEmpty);
    });

    test('readPose copies the logical pose into the destination', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      subLevel.pose.position().set(3, 4, 5);
      subLevel.pose.orientation().set(0, 0, 0, 1);

      final dest = Pose3d();
      final result = pipeline.readPose(subLevel, dest);
      expect(result, same(dest));
      expect(dest.position().x, 3);
      expect(dest.position().y, 4);
      expect(dest.position().z, 5);
    });

    test('teleport writes the sub-level pose, as Java does for a ServerSubLevel', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      final handle = pipeline.addSubLevel(subLevel, Pose3d());

      pipeline.teleport(handle, Vector3d(1, 2, 3), Quaterniond()..fromAxisAngle(Vector3d(0, 1, 0), 0.5));

      expect(subLevel.logicalPose.position().x, 1);
      expect(subLevel.logicalPose.position().y, 2);
      expect(subLevel.logicalPose.position().z, 3);
      expect(subLevel.logicalPose.orientation().y, closeTo(0.24740395925452294, 1e-12));
    });

    test('a foreign body handle is ignored by teleport', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      pipeline.teleport(_ForeignBody(), Vector3d(9, 9, 9), Quaterniond());
      expect(subLevel.logicalPose.position().x, 0);
    });

    test('physicsTick never moves a sub-level', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      final handle = pipeline.addSubLevel(subLevel, Pose3d());
      pipeline
        ..init(Vector3d(0, -9.81, 0), 0.09)
        ..tick()
        ..prePhysicsTicks()
        ..physicsTick(1 / 20)
        ..postPhysicsTicks();

      expect(pipeline.readPose(subLevel, Pose3d()).position().y, 0);
      expect(handle.getLinearVelocity().length, 0);
      expect(handle.getAngularVelocity().length, 0);
    });

    test('the body handle ignores impulses and reports zero velocity', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      final handle = pipeline.addSubLevel(subLevel, Pose3d()) as StaticBodyHandle;
      handle
        ..applyLinearAndAngularImpulse(Vector3d(1, 0, 0), Vector3d(0, 1, 0), true)
        ..applyImpulseAtPoint(Vector3d(0, 1, 0), Vector3d(100, 0, 0))
        ..addLinearAndAngularVelocity(Vector3d(1, 1, 1), Vector3d(1, 1, 1))
        ..applyForcesAndReset(ForceTotal());

      expect(handle.getLinearVelocity().length, 0);
      expect(handle.getAngularVelocity().length, 0);
    });

    test('applyForcesAndReset on a static body resets the total', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      final handle = pipeline.addSubLevel(subLevel, Pose3d()) as StaticBodyHandle;
      final total = ForceTotal()..applyLinearAndAngularImpulse(Vector3d(1, 2, 3), Vector3d(4, 5, 6));
      handle.applyForcesAndReset(total);
      expect(total.getLocalForce().length, 0);
      expect(total.getLocalTorque().length, 0);
    });

    test('boxes and ropes are remembered and never simulated', () {
      final pipeline = StaticPhysicsPipeline();
      final box = pipeline.addBox(BoxPhysicsObject(Pose3d()..position().set(1, 1, 1), Vector3d(1, 1, 1), 2.0));
      final rope = pipeline.addRope(RopePhysicsObject([Vector3d(0, 0, 0), Vector3d(0, 1, 0)], 0.125));

      final boxPose = Pose3d();
      box.readPose(boxPose);
      expect(boxPose.position().x, 1);
      expect(rope.queryPoints().map((p) => p.y), [0.0, 1.0]);
      expect(pipeline.boxes, hasLength(1));
      expect(pipeline.ropes, hasLength(1));

      pipeline
        ..removeBox(box)
        ..removeRope(rope);
      expect(pipeline.boxes, isEmpty);
      expect(pipeline.ropes, isEmpty);
    });

    test('getNextRuntimeId is the Java constant 0', () {
      expect(StaticPhysicsPipeline().getNextRuntimeId(), 0);
    });

    test('dispose forgets every body', () {
      final pipeline = StaticPhysicsPipeline();
      final subLevel = makeSubLevel(FakeLevel(), FakeChunkHost(FakeLevel()), 'a');
      pipeline
        ..addSubLevel(subLevel, Pose3d())
        ..addBox(BoxPhysicsObject(Pose3d(), Vector3d(1, 1, 1), 1.0))
        ..dispose();
      expect(pipeline.bodies, isEmpty);
      expect(pipeline.boxes, isEmpty);
    });
  });

  group('physics constraint configurations', () {
    test('the joint axis indices are the Java enum ordinals', () {
      expect(ConstraintJointAxis.linearX, 0);
      expect(ConstraintJointAxis.linearY, 1);
      expect(ConstraintJointAxis.linearZ, 2);
      expect(ConstraintJointAxis.angularX, 3);
      expect(ConstraintJointAxis.angularY, 4);
      expect(ConstraintJointAxis.angularZ, 5);
      expect(ConstraintJointAxis.all, [0, 1, 2, 3, 4, 5]);
    });

    test('the lock mask bits are 1 << axis, and all is 0x3f', () {
      expect(ConstraintJointAxisMask.linearX, 1);
      expect(ConstraintJointAxisMask.angularZ, 32);
      expect(ConstraintJointAxisMask.all, 0x3f);
      expect(
        ConstraintJointAxisMask.linearX |
            ConstraintJointAxisMask.linearY |
            ConstraintJointAxisMask.linearZ |
            ConstraintJointAxisMask.angularX |
            ConstraintJointAxisMask.angularY |
            ConstraintJointAxisMask.angularZ,
        ConstraintJointAxisMask.all,
      );
    });

    test('every configuration carries its frames unchanged', () {
      final pos1 = Vector3d(1, 2, 3);
      final pos2 = Vector3d(4, 5, 6);
      final quat = Quaterniond()..fromAxisAngle(Vector3d(0, 0, 1), 1.0);

      final rotary = RotaryConstraintConfiguration(pos1, pos2, Vector3d(0, 1, 0), Vector3d(0, 0, 1));
      expect(rotary.pos1, same(pos1));
      expect(rotary.axis2, Vector3d(0, 0, 1));

      final fixed = FixedConstraintConfiguration(pos1, pos2, quat);
      expect(fixed.quatB, same(quat));

      final free = FreeConstraintConfiguration(pos1, pos2, quat);
      expect(free.pos2, same(pos2));

      final generic = GenericConstraintConfiguration(pos1, quat, pos2, quat, ConstraintJointAxisMask.all);
      expect(generic.lockedAxesMask, ConstraintJointAxisMask.all);
      expect(generic, isA<PhysicsConstraintConfiguration>());
    });

    test('RopeAttachmentPoint is start then end', () {
      expect(RopeAttachmentPoint.values, [RopeAttachmentPoint.start, RopeAttachmentPoint.end]);
    });
  });
  group('updateMassDataFromBlockChange', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late SubLevelPhysicsSystem system;
    late ServerSubLevel subLevel;

    setUp(() {
      level = FakeLevel();
      host = FakeChunkHost(level);
      container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      system = SubLevelPhysicsSystem(
        container: container,
        pipeline: StaticPhysicsPipeline(),
        config: SableConfig(),
        serverConfig: SableServerConfig(),
      );
      // `allocateSubLevel` fires `onSubLevelAdded`, which builds the real
      // `MergedMassTracker` over the **empty** plot -- the state every assembly
      // starts from.
      subLevel = container.allocateSubLevel('00000000-0000-0000-0000-0000000000a1', 0, 0, Pose3d())
          as ServerSubLevel;
      subLevel.getPlot().newEmptyChunk(subLevel.getPlot().getCenterChunk());
    });

    test('the first block of an assembly is kept and counted', () {
      final centre = subLevel.getPlot().getCenterBlock();

      system.handleBlockChange(
        centre.$1,
        centre.$2,
        centre.$3,
        'minecraft:air',
        'minecraft:stone',
        subLevelId: subLevel.uniqueId,
      );

      // The bug this pins: the check used the *merged* tracker, which is still
      // the empty one on the first block, so the plot was destroyed and the
      // sub-level removed (`SubLevelPhysicsSystem.java:524-535` validates the
      // self tracker).
      expect(subLevel.isRemoved(), isFalse);
      expect(subLevel.massTracker?.isInvalid(), isFalse);
      expect(subLevel.massTracker?.getMass(), 1.0);
    });

    test('removing the last block still removes the sub-level', () {
      final centre = subLevel.getPlot().getCenterBlock();
      system.handleBlockChange(
        centre.$1,
        centre.$2,
        centre.$3,
        'minecraft:air',
        'minecraft:stone',
        subLevelId: subLevel.uniqueId,
      );
      expect(subLevel.isRemoved(), isFalse);

      system.handleBlockChange(
        centre.$1,
        centre.$2,
        centre.$3,
        'minecraft:stone',
        'minecraft:air',
        subLevelId: subLevel.uniqueId,
      );

      expect(subLevel.isRemoved(), isTrue);
    });
  });
}


/// A body handle that is not the static pipeline's own, to prove the
/// `instanceof ServerSubLevel` guard.
final class _ForeignBody implements RigidBodyHandle {
  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => dest ?? Vector3d();

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => dest ?? Vector3d();

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {}

  @override
  void applyForcesAndReset(ForceTotal forceTotal) {}

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) {}

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  bool get isValid => true;
}