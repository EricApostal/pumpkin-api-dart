// W3: the block/entity API behaviour that is pure logic — lift providers, the
// propeller thrust scaling, entity projection and the collision-callback
// registry. Runs on the VM.
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

final class FakeMassData implements MassData {
  final Vector3d centerOfMass;
  final double inverseMass;

  FakeMassData(this.centerOfMass, [this.inverseMass = 0.1]);

  @override
  Vector3d getCenterOfMass() => centerOfMass;

  @override
  double getInverseMass() => inverseMass;

  @override
  double getMass() => inverseMass == 0.0 ? 0.0 : 1.0 / inverseMass;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.identity();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.identity();

  @override
  bool isInvalid() => false;

  @override
  BoundingBox3ic? getBounds() => null;
}

/// A lift provider that reports fixed scalars.
final class FixedLiftProvider implements BlockSubLevelLiftProvider {
  @override
  Direction sable$getNormal(BState state) => Direction.up;

  @override
  double sable$getParallelDragScalar() => 0.75;

  @override
  double sable$getDirectionlessDragScalar() => 0.0;

  @override
  double sable$getLiftScalar() => 0.0;

  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) => BlockSubLevelLiftProvider.contributeLiftAndDrag(
    this,
    ctx,
    subLevel,
    localPose,
    timeStep,
    linearVelocity,
    angularVelocity,
    linearImpulse,
    angularImpulse,
    group,
  );
}

final class FakeEntity implements SubLevelEntity {
  @override
  Vector3d position = Vector3d();

  @override
  Vector3d eyePosition = Vector3d();

  @override
  double eyeHeight = 1.62;

  @override
  Vector3d lookAngle = Vector3d(0, 0, 1);

  @override
  Vector3d deltaMovement = Vector3d();

  @override
  double boundingBoxHeight = 1.8;

  @override
  double xRot = 0, yRot = 0, yHeadRot = 0;

  @override
  double xOld = 0, yOld = 0, zOld = 0, xo = 0, yo = 0, zo = 0;

  @override
  String typeId = 'minecraft:item';

  @override
  bool isFallingBlock = false;

  @override
  bool isArrow = false;

  @override
  bool isHurtingProjectile = false;

  @override
  double accelerationPower = 0;

  final List<Vector3d> snaps = [];

  @override
  void snapTo(Vector3d value) {
    snaps.add(Vector3d.copy(value));
    position = Vector3d.copy(value);
  }

  @override
  void lookAtFeet(Vector3d target) {}

  @override
  void setPosRaw(Vector3d value) => position = Vector3d.copy(value);
}

void main() {
  late FakeLevel level;
  late FakeChunkHost host;
  late ServerSubLevelContainer container;
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
    subLevel = container.allocateNewSubLevel(Pose3d()) as ServerSubLevel;
    subLevel.massTracker = FakeMassData(Vector3d());
  });

  tearDown(() => SubLevelContainer.unregister(level));

  group('BlockSubLevelLiftProvider', () {
    test('groups providers into 6-connected clusters', () {
      final contexts = [
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        LiftProviderContext((1, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        LiftProviderContext((5, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
      ];

      final groups = BlockSubLevelLiftProvider.groupLiftProviders(contexts);
      expect(groups, hasLength(2));
      expect(groups.first.positions, hasLength(2));
      expect(groups.last.positions, hasLength(1));
    });

    test('does not connect diagonals', () {
      final contexts = [
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        LiftProviderContext((1, 1, 1), const BState('a'), Vector3d(0, 1, 0)),
      ];
      expect(BlockSubLevelLiftProvider.groupLiftProviders(contexts), hasLength(2));
    });

    test('the default scalars match the Java defaults', () {
      final provider = _DefaultLiftProvider();
      expect(provider.sable$getParallelDragScalar(), 0.75);
      expect(provider.sable$getLiftScalar(), 0.475);
      expect(
        BlockSubLevelLiftProvider.defaultDirectionlessDragScalar,
        closeTo(0.06888202261, 1e-12),
      );
      // (-0.75 + sqrt(0.75^2 + 0.475^2)) / 2
      expect(
        provider.sable$getDirectionlessDragScalar(),
        closeTo((-0.75 + math.sqrt(0.75 * 0.75 + 0.475 * 0.475)) / 2, 1e-9),
      );
    });

    test('parallel drag opposes the motion along the normal', () {
      final provider = FixedLiftProvider();
      final linearImpulse = Vector3d();
      final angularImpulse = Vector3d();

      provider.sable$contributeLiftAndDrag(
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        subLevel,
        null,
        0.05,
        Vector3d(0, 2, 0),
        Vector3d(),
        linearImpulse,
        angularImpulse,
      );

      // The impulse is the negative of the computed force.
      expect(linearImpulse.y, lessThan(0));
      expect(linearImpulse.x, closeTo(0, 1e-12));
    });

    test('a zero normal velocity contributes nothing', () {
      final provider = FixedLiftProvider();
      final linearImpulse = Vector3d();
      final angularImpulse = Vector3d();

      provider.sable$contributeLiftAndDrag(
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        subLevel,
        null,
        0.05,
        Vector3d(1, 0, 0),
        Vector3d(),
        linearImpulse,
        angularImpulse,
      );

      expect(linearImpulse.length, closeTo(0, 1e-12));
    });

    test('the scratch vectors are reset after a contribution', () {
      FixedLiftProvider().sable$contributeLiftAndDrag(
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        subLevel,
        null,
        0.05,
        Vector3d(0, 1, 0),
        Vector3d(),
        Vector3d(),
        Vector3d(),
      );

      expect(BlockSubLevelLiftProvider.liftForce.length, 0);
      expect(BlockSubLevelLiftProvider.liftNormal.length, 0);
      expect(BlockSubLevelLiftProvider.liftPos.length, 0);
    });

    test('the group accumulates the drag', () {
      final provider = FixedLiftProvider();
      final group = LiftProviderGroup({(0, 0, 0)});

      provider.sable$contributeLiftAndDrag(
        LiftProviderContext((0, 0, 0), const BState('a'), Vector3d(0, 1, 0)),
        subLevel,
        null,
        0.05,
        Vector3d(0, 2, 0),
        Vector3d(),
        Vector3d(),
        Vector3d(),
        group,
      );

      // The group stores the drag the provider *removes* from the body.
      expect(group.totalDrag.y, lessThan(0));
      expect(group.totalDragStrength, greaterThan(0));
    });
  });

  group('SubLevelHelper entity projection', () {
    test('push then pop round-trips a position', () {
      final pose = subLevel.pose;
      pose.position().set(10, 20, 30);
      pose.orientation().rotateY(math.pi / 2);

      final entity = FakeEntity()..position = Vector3d(11, 21, 30);

      SubLevelHelper.pushEntityLocal(subLevel, entity);
      expect(entity.position.x, isNot(closeTo(11, 1e-6)));

      SubLevelHelper.popEntityLocal(subLevel, entity);
      expect(entity.position.x, closeTo(11, 1e-6));
      expect(entity.position.y, closeTo(21, 1e-6));
      expect(entity.position.z, closeTo(30, 1e-6));
    });

    test('pop restores the cached rotations', () {
      final entity = FakeEntity()
        ..xRot = 12
        ..yRot = 34
        ..yHeadRot = 56;

      SubLevelHelper.pushEntityLocal(subLevel, entity);
      SubLevelHelper.popEntityLocal(subLevel, entity);

      expect(entity.xRot, 12);
      expect(entity.yRot, 34);
      expect(entity.yHeadRot, 56);
    });

    test('delta movement is transformed out again', () {
      subLevel.pose.orientation().rotateY(math.pi / 2);
      final entity = FakeEntity()..deltaMovement = Vector3d(1, 0, 0);

      SubLevelHelper.pushEntityLocal(subLevel, entity);
      SubLevelHelper.popEntityLocal(subLevel, entity);

      expect(entity.deltaMovement.x, closeTo(1, 1e-9));
      expect(entity.deltaMovement.z, closeTo(0, 1e-9));
    });
  });

  group('SubLevelHelper lookups', () {
    test('getContaining finds the sub-level whose plot holds the chunk', () {
      final centre = subLevel.getPlot().getCenterBlock();
      final found = SubLevelHelper.getContaining(level, centre);
      expect(found?.uniqueId, subLevel.uniqueId);
    });

    test('getContaining returns null outside the plot yard', () {
      expect(SubLevelHelper.getContaining(level, (0, 0, 0)), isNull);
    });

    test('getVelocity of a point on a static sub-level is zero', () {
      final velocity = SubLevelHelper.getVelocity(level, Vector3d(0, 0, 0));
      expect(velocity.length, 0);
    });

    test('wind providers subtract from the air-relative velocity', () {
      SubLevelHelper.registerWindProvider((pos, level) => Vector3d(1, 0, 0));
      addTearDown(SubLevelHelper.clearWindProviders);

      final velocity = SubLevelHelper.getVelocityRelativeToAir(level, Vector3d());
      expect(velocity.x, closeTo(-1, 1e-12));
    });

    test('the dependency chain follows intersecting sub-levels', () {
      final chain = SubLevelHelper.getLoadingDependencyChain(subLevel);
      expect(chain, contains(subLevel));
    });

    test('the connected chain of a lone sub-level is itself', () {
      expect(SubLevelHelper.getConnectedChain(subLevel), {subLevel});
    });
  });

  group('BlockWithSubLevelCollisionCallback', () {
    test('registered callbacks are found by block key', () {
      final callback = _RecordingCallback();
      BlockWithSubLevelCollisionCallback.register('test:block', callback);
      addTearDown(() => BlockWithSubLevelCollisionCallback.unregister('test:block'));

      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(const BState('test:block')),
        same(callback),
      );
      expect(BlockWithSubLevelCollisionCallback.hasCallback(const BState('test:block')), isTrue);
      expect(BlockWithSubLevelCollisionCallback.hasCallback(const BState('test:other')), isFalse);
    });

    test('the fragile property falls back to the installed callback', () {
      final callback = _RecordingCallback();
      BlockWithSubLevelCollisionCallback.fragileCallback = callback;
      addTearDown(() => BlockWithSubLevelCollisionCallback.fragileCallback = null);

      expect(
        BlockWithSubLevelCollisionCallback.sable$getCallbackFor(
          const BState('minecraft:oak_leaves', {'fragile': 'true'}),
        ),
        same(callback),
      );
    });

    test('onCollision packs the tangent motion and the removal flag', () {
      final callback = _RecordingCallback(remove: true);
      final packed = callback.onCollision(1, 2, 3, 0, 0, 0, 0.5, 0, 0, 4.0, true);

      expect(packed, [0.0, 0.0, 0.0, 1.0]);
      expect(callback.hitBlockPos, (1, 2, 3));
      expect(callback.otherHitBlockPos, (0, 0, 0));
      expect(callback.impactVelocity, 4.0);
    });
  });

  group('VoxelColliderDataImpl', () {
    test('adds and clears boxes', () {
      final data = VoxelColliderDataImpl();
      data.addBox(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      expect(data.boxes.single, [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]);
      data.clearBoxes();
      expect(data.boxes, isEmpty);
    });
  });
}

/// A provider that keeps every default scalar.
final class _DefaultLiftProvider implements BlockSubLevelLiftProvider {
  @override
  Direction sable$getNormal(BState state) => Direction.up;

  @override
  double sable$getParallelDragScalar() => BlockSubLevelLiftProvider.defaultParallelDragScalar;

  @override
  double sable$getDirectionlessDragScalar() => BlockSubLevelLiftProvider.defaultDirectionlessDragScalar;

  @override
  double sable$getLiftScalar() => BlockSubLevelLiftProvider.defaultLiftScalar;

  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) => BlockSubLevelLiftProvider.contributeLiftAndDrag(
    this,
    ctx,
    subLevel,
    localPose,
    timeStep,
    linearVelocity,
    angularVelocity,
    linearImpulse,
    angularImpulse,
    group,
  );
}

final class _RecordingCallback implements BlockSubLevelCollisionCallback {
  final bool remove;

  (int, int, int)? hitBlockPos;
  (int, int, int)? otherHitBlockPos;
  double impactVelocity = 0;

  _RecordingCallback({this.remove = false});

  @override
  List<double> onCollision(
    int x,
    int y,
    int z,
    int otherX,
    int otherY,
    int otherZ,
    double x1,
    double y1,
    double z1,
    double impactVelocity,
    bool hasOtherBlock,
  ) {
    final result = sable$onCollision(
      (x, y, z),
      hasOtherBlock ? (otherX, otherY, otherZ) : null,
      Vector3d(x1, y1, z1),
      impactVelocity,
    );
    final motion = result.tangentMotion;
    return [motion.x, motion.y, motion.z, result.removeCollision ? 1.0 : 0.0];
  }

  @override
  CollisionResult sable$onCollision(
    (int, int, int) hitBlockPos,
    (int, int, int)? otherHitBlockPos,
    Vector3d impactPosition,
    double impactVelocity,
  ) {
    this.hitBlockPos = hitBlockPos;
    this.otherHitBlockPos = otherHitBlockPos;
    this.impactVelocity = impactVelocity;
    return CollisionResult(Vector3d(), remove);
  }
}
