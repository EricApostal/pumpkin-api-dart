// The physics pipeline, driven through the real Jolt core module.
//
// `package:test` runs on the Dart VM, so the module is instantiated by a Node
// sidecar and the pipeline talks to it through `NodeJolt` (a `JoltAbi` /
// `JoltMemory` implementation). Everything above that transport is the shipping
// code: `JoltPhysicsPipeline`, its marshalling, and the ABI in
// `native/jolt/src/jolt_abi.cpp`.
import 'dart:io';
import 'dart:math' as math;

import 'package:sable/sable.dart';
import 'package:sable_jolt/sable_jolt.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/node_jolt.dart';

const _wasm = 'native/jolt/jolt.wasm';

final class TestMassData implements MassData {
  final Vector3d centerOfMass;
  final double mass;
  final Matrix3d inertia;

  TestMassData(this.centerOfMass, this.mass, this.inertia);

  TestMassData.isotropic(this.centerOfMass, this.mass, double i)
    : inertia = Matrix3d(i, 0.0, 0.0, 0.0, i, 0.0, 0.0, 0.0, i);

  @override
  Vector3d getCenterOfMass() => centerOfMass;

  @override
  double getInverseMass() => 1.0 / mass;

  @override
  double getMass() => mass;

  @override
  Matrix3d getInertiaTensor() => inertia;

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.copy(inertia)..invert();

  @override
  bool isInvalid() => mass <= 0.0;

  @override
  BoundingBox3ic? getBounds() =>
      BoundingBox3i.values(-4, -4, -4, 4, 4, 4);
}

/// A section whose top layer is a full cube of [collider].
List<int> _floorSection(int collider) {
  final data = List<int>.filled(4096, 0);
  for (var bx = 0; bx < 16; bx++) {
    for (var bz = 0; bz < 16; bz++) {
      data[bx + (bz << 4) + (15 << 8)] =
          packBlockState(collider, VoxelPhysicsState.face);
    }
  }
  return data;
}

/// A section with a single solid block at its local origin.
List<int> _singleBlockSection(int collider) {
  final data = List<int>.filled(4096, 0);
  data[0] = packBlockState(collider, VoxelPhysicsState.face);
  return data;
}

bool _nodeAvailable() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final available = File(_wasm).existsSync() && _nodeAvailable();
  final skip = available
      ? null
      : 'needs node and $_wasm (run native/jolt/build.sh)';

  late NodeJolt host;

  setUpAll(() async {
    if (!available) {
      return;
    }
    host = await NodeJolt.start(_wasm);
  });

  tearDownAll(() => host.close());

  late JoltPhysicsPipeline pipeline;

  setUp(() {
    pipeline = JoltPhysicsPipeline(abi: host, memory: host);
    pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
  });

  tearDown(() => pipeline.dispose());

  test('the module reports its ABI and Jolt version', () {
    expect(host.abiVersion(), 1);
    // `JPH_VERSION_ID` (`Jolt/Core/Core.h:88`):
    // features << 24 | major << 16 | minor << 8 | patch, for 5.6.1.
    expect(host.version(), (5 << 16) | (6 << 8) | 1);
  }, skip: skip);

  test('a box dropped on a voxel floor settles at the expected height', () {
    final collider = pipeline.registerVoxelCollider(const BlockColliderData());
    pipeline.handleChunkSectionAddition(
      0,
      -1,
      0,
      _floorSection(collider),
      global: true,
    );

    final pose = Pose3d()..position().set(0.0, 5.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );

    for (var i = 0; i < 120; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }

    final settled = Pose3d();
    box.readPose(settled);
    // The floor's top surface is y = 0, so a 1x1x1 box rests at 0.5 minus the
    // contact slop.
    expect(settled.position().y, closeTo(0.48, 0.02));
    expect(settled.position().x.abs(), lessThan(0.1));
    expect(settled.position().z.abs(), lessThan(0.1));

    for (var i = 0; i < 60; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final still = Pose3d();
    box.readPose(still);
    expect(still.position().y, closeTo(settled.position().y, 1e-3));
    expect(pipeline.isActive(box), isFalse, reason: 'the box falls asleep');
  }, skip: skip);

  test('a sub-level body with a voxel chunk collider collides with a box', () {
    final level = TestLevel();
    SubLevelContainer.register(TestContainer(level, TestChunkHost()));
    addTearDown(() => SubLevelContainer.unregister(level));

    final subLevel = ServerSubLevel(
      level,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
      Pose3d()..position().set(0.0, 3.0, 0.0),
      runtimeId: 7,
    );

    final body = pipeline.addSubLevel(subLevel, subLevel.pose);
    expect(subLevel.physicsBody, same(body));

    final collider = pipeline.registerVoxelCollider(const BlockColliderData());
    // The static level: a floor at y = 0.
    pipeline.handleChunkSectionAddition(
      0,
      -1,
      0,
      _floorSection(collider),
      global: true,
    );
    // One block at plot (0,0,0): a unit cube around the body's center of mass.
    pipeline.handleChunkSectionAddition(
      0,
      0,
      0,
      _singleBlockSection(collider),
      global: false,
      subLevelRuntimeId: 7,
    );
    subLevel.massTracker = TestMassData.isotropic(
      Vector3d(0.5, 0.5, 0.5),
      1.0,
      1.0,
    );
    pipeline.onStatsChanged(subLevel);
    expect(pipeline.massOf(body), closeTo(1.0, 1e-4));

    // The sub-level falls onto the floor and comes to rest with its block on
    // top of it.
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final rest = pipeline.readPose(subLevel, Pose3d());
    expect(rest.position().y, closeTo(0.48, 0.05));

    // A box dropped onto the sub-level block stops on it instead of reaching
    // the floor.
    final boxPose = Pose3d()..position().set(0.0, 4.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(boxPose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final boxRest = Pose3d();
    box.readPose(boxRest);
    final blockTop = pipeline.readPose(subLevel, Pose3d()).position().y + 0.5;
    expect(boxRest.position().y, greaterThan(0.9));
    expect(boxRest.position().y, closeTo(blockTop + 0.48, 0.1));
  }, skip: skip);

  test('removing the sub-level block lets the box fall through', () {
    final level = TestLevel();
    SubLevelContainer.register(TestContainer(level, TestChunkHost()));
    addTearDown(() => SubLevelContainer.unregister(level));

    final subLevel = ServerSubLevel(
      level,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
      Pose3d()..position().set(0.0, 2.0, 0.0),
      runtimeId: 11,
    );
    pipeline.addSubLevel(subLevel, subLevel.pose);
    final collider = pipeline.registerVoxelCollider(const BlockColliderData());
    pipeline.handleChunkSectionAddition(
      0,
      -1,
      0,
      _floorSection(collider),
      global: true,
    );
    pipeline.handleChunkSectionAddition(
      0,
      0,
      0,
      _singleBlockSection(collider),
      global: false,
      subLevelRuntimeId: 11,
    );
    subLevel.massTracker = TestMassData.isotropic(
      Vector3d(0.5, 0.5, 0.5),
      1.0,
      1.0,
    );
    pipeline.onStatsChanged(subLevel);

    final boxPose = Pose3d()..position().set(0.0, 4.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(boxPose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    // Long enough for the box to land on the sub-level block, which sits on
    // the floor at y = 0.48: the box stops near 1.4, well above the floor.
    for (var i = 0; i < 90; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final resting = Pose3d();
    box.readPose(resting);
    expect(resting.position().y, greaterThan(1.0));

    // `changeBlock` with an empty state removes the block's boxes, so the box
    // has nothing left to rest on but the floor.
    pipeline.handleBlockChange(0, 0, 0, 0);
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final fallen = Pose3d();
    box.readPose(fallen);
    expect(fallen.position().y, lessThan(resting.position().y - 0.5));
  }, skip: skip);

  test('removing a sub-level chunk section drops its colliders', () {
    final level = TestLevel();
    SubLevelContainer.register(TestContainer(level, TestChunkHost()));
    addTearDown(() => SubLevelContainer.unregister(level));

    final subLevel = ServerSubLevel(
      level,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
      Pose3d()..position().set(0.0, 2.0, 0.0),
      runtimeId: 13,
    );
    pipeline.addSubLevel(subLevel, subLevel.pose);
    final collider = pipeline.registerVoxelCollider(const BlockColliderData());
    pipeline.handleChunkSectionAddition(
      0,
      -1,
      0,
      _floorSection(collider),
      global: true,
    );
    pipeline.handleChunkSectionAddition(
      0,
      0,
      0,
      _singleBlockSection(collider),
      global: false,
      subLevelRuntimeId: 13,
    );
    subLevel.massTracker = TestMassData.isotropic(
      Vector3d(0.5, 0.5, 0.5),
      1.0,
      1.0,
    );
    pipeline.onStatsChanged(subLevel);

    final boxPose = Pose3d()..position().set(0.0, 4.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(boxPose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    for (var i = 0; i < 90; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final resting = Pose3d();
    box.readPose(resting);
    expect(resting.position().y, greaterThan(1.0));

    // The section's ticket expired: the engine must forget the block's
    // colliders too, not just the Dart-side store.
    pipeline.handleChunkSectionRemoval(0, 0, 0);
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final fallen = Pose3d();
    box.readPose(fallen);
    expect(fallen.position().y, lessThan(resting.position().y - 0.5));
  }, skip: skip);

  test('a section in a plot reaches the sub-level body without a runtime id', () {
    // The call `SubLevelPhysicsSystem.handleChunkSectionAddition` makes
    // (`physics_system.dart:419`): `global: false`, no `subLevelRuntimeId`. The
    // pipeline has to find the owning body through the plot grid
    // (`RapierPhysicsPipeline.java:358-365`), and the module has to receive that
    // body's handle — before the fix this threw, and with body 0 the native call
    // is a no-op (`jolt_abi.cpp:1372-1376`).
    final level = TestLevel();
    final container = TestServerContainer(level, TestChunkHost());
    SubLevelContainer.register(container);
    addTearDown(() => SubLevelContainer.unregister(level));

    final subLevel =
        container.allocateSubLevel(
              'uuid',
              0,
              0,
              Pose3d()..position().set(0.0, 3.0, 0.0),
            )
            as ServerSubLevel;
    pipeline.addSubLevel(subLevel, subLevel.pose);
    final collider = pipeline.registerVoxelCollider(const BlockColliderData());

    // The first chunk of the first plot: the grid starts at
    // `SubLevelContainer.defaultOrigin` plots, and a plot is
    // `1 << SubLevelContainer.defaultLogPlotSize` (= 7) chunks wide.
    const plotChunk = SubLevelContainer.defaultOrigin * (1 << 7);

    expect(
      () => pipeline.handleChunkSectionAddition(
        plotChunk,
        0,
        plotChunk,
        _singleBlockSection(collider),
        global: false,
      ),
      returnsNormally,
    );
    expect(pipeline.blocksOf(subLevel)!.hasSection(plotChunk, 0, plotChunk), isTrue);
    expect(
      pipeline.levelBlocks.hasSection(plotChunk, 0, plotChunk),
      isFalse,
      reason: 'a plot section is not static level geometry',
    );

    expect(
      () => pipeline.handleChunkSectionRemoval(plotChunk, 0, plotChunk),
      returnsNormally,
    );
    expect(pipeline.blocksOf(subLevel)!.hasSection(plotChunk, 0, plotChunk), isFalse);
  }, skip: skip);

  test('a hinge holds a box to the world', () {
    final pose = Pose3d()..position().set(0.0, 2.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    final hinge = pipeline.addHinge(
      null,
      box,
      Vector3d(0.0, 2.5, 0.0),
      Vector3d(0.0, 0.5, 0.0),
      Vector3d(1.0, 0.0, 0.0),
      Vector3d(1.0, 0.0, 0.0),
    );
    expect(hinge.isValid, isTrue);

    for (var i = 0; i < 120; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final held = Pose3d();
    box.readPose(held);
    // Free fall would be ~20 m; the hinge keeps the box at its anchor.
    expect(held.position().y, closeTo(2.0, 0.15));
    final linear = Vector3d();
    final angular = Vector3d();
    hinge.getJointImpulses(linear, angular);
    expect(linear.length + angular.length, greaterThanOrEqualTo(0.0));

    hinge.remove();
    expect(hinge.isValid, isFalse);
  }, skip: skip);

  test('a hinge motor turns the box to its target angle', () {
    // Gravity off: the only torque is the motor's.
    pipeline.setGravity(Vector3d());

    final pose = Pose3d()..position().set(0.0, 2.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    final hinge = pipeline.addHinge(
      null,
      box,
      Vector3d(0.0, 2.0, 0.0),
      Vector3d(0.0, 0.0, 0.0),
      Vector3d(0.0, 1.0, 0.0),
      Vector3d(0.0, 1.0, 0.0),
    );

    // Without a motor the box stays where it is.
    for (var i = 0; i < 60; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final before = Pose3d();
    box.readPose(before);
    expect(_rotationAngle(before.orientation()), lessThan(0.05));

    // `setMotor` with Rapier's gains: stiffness 10, damping 2 on the rotary
    // joint's `ANGULAR_X` axis (`RotaryConstraintHandle.DEFAULT_AXIS`), which
    // the Jolt handle routes to the hinge's motor slot. `JoltJointHandle`
    // converts the gains to 1.23 Hz at a 0.775 damping ratio, and the ABI
    // calls `HingeConstraint::SetTargetAngle` (`jolt_abi.cpp:1602-1640`).
    hinge.setMotor(ConstraintJointAxis.angularX, math.pi / 2, 10.0, 2.0, false, 0.0);
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final after = Pose3d();
    box.readPose(after);
    // The target is a quarter turn about +Y.
    expect(_rotationAngle(after.orientation()), closeTo(math.pi / 2, 0.1));
    expect(after.position().y, closeTo(2.0, 0.05));

    hinge.remove();
  }, skip: skip);

  test('a six-DOF motor drives the box to its target position', () {
    // The assembler's alignment joint is a free six-DOF joint
    // (`FreeConstraintConfiguration`), so its linear motors are axes 0-2.
    pipeline.setGravity(Vector3d());

    final pose = Pose3d()..position().set(0.0, 2.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    final joint = pipeline.addSixDof(
      null,
      box,
      Vector3d(0.0, 2.0, 0.0),
      Quaterniond(),
      Vector3d(0.0, 0.0, 0.0),
      Quaterniond(),
    );

    // The box sleeps with the joint holding it still.
    for (var i = 0; i < 60; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final before = Pose3d();
    box.readPose(before);
    expect(before.position().x, closeTo(0.0, 0.01));

    // 100 N/m at 20 N·s/m on a 1 kg box: 1.59 Hz, damping ratio 1.0.
    joint.setMotor(0, 1.0, 100.0, 20.0, false, 0.0);
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final after = Pose3d();
    box.readPose(after);
    expect(after.position().x, closeTo(1.0, 0.05));
    expect(after.position().y, closeTo(2.0, 0.05));

    joint.remove();
  }, skip: skip);

  test('a six-DOF angular motor turns the box to its target angle', () {
    // The assembler holds the three angular axes at zero with a stiff,
    // overdamped motor; here the target is a quarter turn so the motion is
    // observable.
    pipeline.setGravity(Vector3d());

    final pose = Pose3d()..position().set(0.0, 2.0, 0.0);
    final box = pipeline.addBox(
      BoxPhysicsObject(pose, Vector3d(0.5, 0.5, 0.5), 1.0),
    );
    final joint = pipeline.addSixDof(
      null,
      box,
      Vector3d(0.0, 2.0, 0.0),
      Quaterniond(),
      Vector3d(0.0, 0.0, 0.0),
      Quaterniond(),
    );

    for (var i = 0; i < 60; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final before = Pose3d();
    box.readPose(before);
    expect(_rotationAngle(before.orientation()), lessThan(0.01));

    // The assembler's angular gains (`AssemblyAlignmentMotors`).
    joint.setMotor(ConstraintJointAxis.angularY, math.pi / 2, 13000.0, 1000.0, false, 0.0);
    for (var i = 0; i < 240; i++) {
      pipeline.physicsTick(1.0 / 60.0);
    }
    final after = Pose3d();
    box.readPose(after);
    expect(_rotationAngle(after.orientation()), closeTo(math.pi / 2, 0.05));
    expect(after.position().y, closeTo(2.0, 0.02));

    joint.remove();
  }, skip: skip);
}

/// The unsigned angle of [q] in radians.
double _rotationAngle(Quaterniond q) =>
    2 * math.acos(q.w.clamp(-1.0, 1.0).toDouble());
