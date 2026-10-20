// Tests for the physics config and force contributors: the block property
// table, the floating-block controller and the reaction wheel manager.
// create's block-state type is not exported from its public barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Wheel implements BlockEntitySubLevelReactionWheel {
  final Vector3d velocity;

  _Wheel(this.velocity);

  @override
  void sable$getAngularVelocity(Vector3d angularVelocity) =>
      angularVelocity.set(velocity.x, velocity.y, velocity.z);

  @override
  BState getBlockState() => const BState('minecraft:iron_block');
}

final class _Body implements FloatingBlockBody {
  @override
  Vector3d centerOfMass = Vector3d();

  @override
  double mass = 100;

  @override
  Matrix3d inverseInertiaTensor = Matrix3d();

  @override
  FloatingBlockMaterial? materialOf(String state) =>
      state == 'sable:floater' ? const FloatingBlockMaterial(liftStrength: 1.0) : null;

  @override
  double floatingScaleOf(String state) => 1.0;

  @override
  double pressureAt(Vector3d worldPosition) => 1.0;
}

final class _Handle implements RigidBodyHandle {
  Vector3d lastTorque = Vector3d();
  bool applied = false;

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {
    lastTorque = Vector3d(angular.x, angular.y, angular.z);
    applied = true;
  }

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  void applyForcesAndReset(Vector3d force) {}

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).zero();

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).zero();

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}
}

void main() {
  group('PhysicsBlockPropertiesTable', () {
    test('defaults match PhysicsBlockPropertyTypes', () {
      final table = PhysicsBlockPropertiesTable();
      final values = table.resolveStateString('minecraft:stone');

      expect(values.mass, 1.0);
      expect(values.volume, 1.0);
      expect(values.friction, 1.0);
      expect(values.restitution, 0.0);
      expect(values.floatingScale, 1.0);
      expect(values.fragile, isFalse);
      expect(values.floatingMaterial, isNull);
      expect(values.inertia, isNull);
    });

    test('a higher priority wins property by property', () {
      final table = PhysicsBlockPropertiesTable()
        ..setDefinitions([
          const PhysicsBlockPropertiesDefinition(
            selector: TagOrElementLocation('minecraft:stone'),
            priority: 100,
            properties: {PhysicsBlockPropertyTypes.mass: 5.0, PhysicsBlockPropertyTypes.friction: 0.2},
          ),
          const PhysicsBlockPropertiesDefinition(
            selector: TagOrElementLocation('minecraft:stone'),
            priority: 200,
            properties: {PhysicsBlockPropertyTypes.mass: 9.0},
          ),
        ]);

      final values = table.resolveStateString('minecraft:stone');
      expect(values.mass, 9.0);
      // The lower priority definition still owns friction.
      expect(values.friction, 0.2);
    });

    test('a matching override replaces the base property', () {
      final table = PhysicsBlockPropertiesTable()
        ..setDefinitions([
          PhysicsBlockPropertiesDefinition(
            selector: const TagOrElementLocation('minecraft:oak_stairs'),
            properties: const {PhysicsBlockPropertyTypes.mass: 2.0},
            overrides: {
              const BlockStateConditionSet([BlockStateCondition('waterlogged', 'true')]): const {
                PhysicsBlockPropertyTypes.mass: 8.0,
              },
            },
          ),
        ]);

      expect(table.resolveStateString('minecraft:oak_stairs[facing=north]').mass, 2.0);
      expect(
        table.resolveStateString('minecraft:oak_stairs[facing=north,waterlogged=true]').mass,
        8.0,
      );
    });

    test('a tag selector uses the installed tag lookup', () {
      final table = PhysicsBlockPropertiesTable();
      table.blockInTag = (blockId, tagId) =>
          tagId == 'minecraft:logs' && blockId.startsWith('minecraft:oak');
      table.setDefinitions([
          const PhysicsBlockPropertiesDefinition(
            selector: TagOrElementLocation('minecraft:logs', tag: true),
            properties: {PhysicsBlockPropertyTypes.mass: 3.0},
          ),
        ]);

      expect(table.resolveStateString('minecraft:oak_log').mass, 3.0);
      expect(table.resolveStateString('minecraft:stone').mass, 1.0);
    });

    test('a non-solid block has no mass and no inertia', () {
      final table = PhysicsBlockPropertiesTable();
      expect(table.massOf('minecraft:stone', false), 0.0);
      expect(table.inertiaOf('minecraft:stone', false), isNull);
    });

    test('block state strings parse their properties', () {
      final key = BlockStateKey.parse('minecraft:oak_stairs[facing=north,half=bottom]');
      expect(key.blockId, 'minecraft:oak_stairs');
      expect(key.properties, {'facing': 'north', 'half': 'bottom'});
      expect(BlockStateKey.parse('minecraft:stone').properties, isEmpty);
    });

    test('an unknown property id is rejected', () {
      expect(
        () => PhysicsBlockPropertyValues.defaults.apply({'sable:nope': 1.0}),
        throwsArgumentError,
      );
    });
  });

  group('FloatingBlockController', () {
    test('a cluster of one block gets lift along the gravity normal', () {
      final body = _Body();
      final controller = FloatingBlockController(body);
      controller.addFloatingBlock('sable:floater', Vector3d(0, 0, 0));

      final linear = Vector3d();
      final angular = Vector3d();
      controller.physicsTick(
        1.0,
        0.05,
        Vector3d(),
        Vector3d(),
        linear,
        angular,
        gravity: Vector3d(0, -11, 0),
      );

      // Lift is opposite gravity, and non-zero for a lifting material.
      expect(linear.y, greaterThan(0));
      expect(linear.x, closeTo(0, 1e-9));
      expect(linear.z, closeTo(0, 1e-9));
    });

    test('a material without lift contributes nothing', () {
      final body = _Body();
      final controller = FloatingBlockController(body);
      controller.addFloatingBlock('minecraft:stone', Vector3d(0, 0, 0));

      final linear = Vector3d();
      final angular = Vector3d();
      controller.physicsTick(
        1.0,
        0.05,
        Vector3d(),
        Vector3d(),
        linear,
        angular,
        gravity: Vector3d(0, -11, 0),
      );

      expect(linear, Vector3d());
      expect(controller.needsTicking(), isFalse);
    });

    test('a queued removal empties the cluster', () {
      final body = _Body();
      final controller = FloatingBlockController(body);
      controller.queueAddFloatingBlock('sable:floater', (0, 0, 0));
      controller.physicsTick(
        1.0,
        0.05,
        Vector3d(),
        Vector3d(),
        Vector3d(),
        Vector3d(),
        gravity: Vector3d(0, -11, 0),
      );
      expect(controller.needsTicking(), isTrue);

      controller.queueRemoveFloatingBlock('sable:floater', (0, 0, 0));
      controller.physicsTick(
        1.0,
        0.05,
        Vector3d(),
        Vector3d(),
        Vector3d(),
        Vector3d(),
        gravity: Vector3d(0, -11, 0),
      );
      expect(controller.needsTicking(), isFalse);
    });
  });

  group('ReactionWheelManager', () {
    late ServerSubLevel subLevel;
    late ServerSubLevelContainer container;

    setUp(() {
      SubLevelContainer.clearAll();
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      SubLevelContainer.register(container);
      subLevel = container.allocateSubLevel(
        '00000000-0000-0000-0000-000000000009',
        0,
        0,
        Pose3d(),
      ) as ServerSubLevel;
    });

    test('a spinning wheel applies angular momentum the first tick only', () {
      final manager = ReactionWheelManager(subLevel, PhysicsBlockPropertiesTable());
      subLevel.getPlot().blockEntityReactionWheels[(0, 0, 0)] = _Wheel(Vector3d(0, 5, 0));

      final handle = _Handle();
      manager.physicsTick(handle);

      expect(handle.applied, isTrue);
      // Momentum = ω · inertia · mass = 5 · (1/6) · 1.
      expect(handle.lastTorque.y, closeTo(5 / 6.0, 1e-9));

      // A constant speed applies nothing more.
      handle.applied = false;
      manager.physicsTick(handle);
      expect(handle.lastTorque.y, closeTo(0.0, 1e-9));
    });

    test('a stopped wheel needs no ticking', () {
      final manager = ReactionWheelManager(subLevel, PhysicsBlockPropertiesTable());
      expect(manager.needsTicking(), isFalse);
    });
  });
}
