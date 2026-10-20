import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart' show Quaterniond, Vector3d;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

void main() {
  group('BearingSlowdownController', () {
    test('detects quarter and half symmetry', () {
      // A four-fold symmetric block set: one block and its three rotations.
      final blocks = <(int, int, int), String>{
        (1, 0, 0): 'minecraft:stone',
        (0, 0, 1): 'minecraft:stone',
        (-1, 0, 0): 'minecraft:stone',
        (0, 0, -1): 'minecraft:stone',
      };
      expect(
        BearingSlowdownController.symmetryOf(blocks, Direction.up),
        ContraptionSymmetry.quarter,
      );

      final half = <(int, int, int), String>{
        (1, 0, 0): 'minecraft:stone',
        (-1, 0, 0): 'minecraft:stone',
        (0, 0, 2): 'minecraft:dirt',
        (0, 0, -2): 'minecraft:dirt',
      };
      expect(
        BearingSlowdownController.symmetryOf(half, Direction.up),
        ContraptionSymmetry.half,
      );

      final none = <(int, int, int), String>{(1, 0, 0): 'minecraft:stone'};
      expect(
        BearingSlowdownController.symmetryOf(none, Direction.up),
        ContraptionSymmetry.none,
      );
    });

    test('rotate90 turns a position a quarter around the axis', () {
      expect(BearingSlowdownController.rotate90((1, 0, 0), Direction.up), (0, 0, 1));
      expect(BearingSlowdownController.rotate90((0, 0, 1), Direction.up), (-1, 0, 0));
    });

    test('the angle ends exactly on the target and the speed on zero', () {
      final controller = BearingSlowdownController()
        ..generate(
          maxTime: 10,
          initialAngle: 12,
          initialVelocity: 20,
          symmetry: ContraptionSymmetry.quarter,
        );

      var guard = 0;
      while (!controller.stepGoal() && guard++ < 100) {}

      expect(guard, lessThan(100));
      expect(controller.countdown, 0);
      expect(controller.angle(0), controller.targetStoppingPoint);
      expect(controller.speed(0), 0);
      // The stop point is a multiple of the symmetry angle.
      expect(controller.targetStoppingPoint % 90, 0);
    });

    test('a saved controller round-trips', () {
      final controller = BearingSlowdownController()
        ..generate(
          maxTime: 5,
          initialAngle: 3,
          initialVelocity: 9,
          symmetry: ContraptionSymmetry.half,
        );
      final copy = BearingSlowdownController()..read(controller.write());
      expect(copy.targetStoppingPoint, controller.targetStoppingPoint);
      expect(copy.symmetry, ContraptionSymmetry.half);
      expect(copy.countdown, controller.countdown);
    });
  });

  group('SimMathUtils', () {
    test('clampIntoCone keeps an inside vector and normalizes an outside one', () {
      final inside = SimMathUtils.clampIntoCone(
        Vector3d(0, 1, 0.1),
        Vector3d(0, 1, 0),
        0.5,
      );
      expect(inside.length, closeTo(1, 1e-9));

      final outside = SimMathUtils.clampIntoCone(
        Vector3d(1, 1, 0),
        Vector3d(0, 1, 0),
        0.1,
      );
      expect(outside.length, closeTo(1, 1e-9));
      final angle = (outside.y / outside.length).clamp(-1.0, 1.0);
      expect(angle, greaterThan(0.9));
    });

    test('isInCylinder bounds length and radius', () {
      final axis = Vector3d(0, 1, 0);
      expect(SimMathUtils.isInCylinder(axis, Vector3d(0, 5, 0), 10, 1), isTrue);
      expect(SimMathUtils.isInCylinder(axis, Vector3d(0, 11, 0), 10, 1), isFalse);
      expect(SimMathUtils.isInCylinder(axis, Vector3d(2, 5, 0), 10, 1), isFalse);
    });

    test('smoothStep is the Hermite curve', () {
      expect(SimMathUtils.smoothStep(0), 0);
      expect(SimMathUtils.smoothStep(1), 1);
      expect(SimMathUtils.smoothStep(0.5), 0.5);
    });

    test('closestYaw of the identity is zero', () {
      expect(SimMathUtils.closestYaw(Quaterniond()), 0);
    });

    test('the grid snapping keeps the closest quaternion', () {
      final snapped = SimMathUtils.clampQuaternionToGrid(
        Quaterniond(0.01, 0.0, 0.0, 1.0)..normalize(),
        GridQuats.all.quaternions,
      );
      expect(snapped.w.abs(), closeTo(1, 1e-6));
    });
  });

  group('SymmetricSail', () {
    test('the normal follows the sail axis', () {
      const provider = SymmetricSailLiftProvider();
      expect(provider.sable$getNormal(const BState('simulated:white_symmetric_sail', {'axis': 'x'})), Direction.east);
      expect(provider.sable$getNormal(const BState('simulated:white_symmetric_sail', {'axis': 'z'})), Direction.south);
      expect(provider.sable$getNormal(const BState('simulated:white_symmetric_sail', {'axis': 'y'})), Direction.up);
    });

    test('the lift and drag scalars match the Java block', () {
      const provider = SymmetricSailLiftProvider();
      expect(provider.sable$getLiftScalar(), 0);
      expect(provider.sable$getParallelDragScalar(), 1.75);
    });

    test('dyeing an undyed sail colours that block only', () {
      final states = <(int, int, int), BState>{
        (0, 0, 0): const BState('simulated:white_symmetric_sail', {'axis': 'y'}),
        (1, 0, 0): const BState('simulated:white_symmetric_sail', {'axis': 'y'}),
      };

      SymmetricSailDye.applyDye(
        state: states[(0, 0, 0)]!,
        colour: 'red',
        neighbourAt: (offset) => states[offset] ?? BState.air,
        setAt: (offset, newState) => states[offset] = newState,
      );

      expect(states[(0, 0, 0)]!.key, 'simulated:red_symmetric_sail');
      expect(states[(1, 0, 0)]!.key, 'simulated:white_symmetric_sail');
    });

    test('dyeing with the sail\'s own colour spreads over the sheet', () {
      final states = <(int, int, int), BState>{
        (0, 0, 0): const BState('simulated:red_symmetric_sail', {'axis': 'y'}),
        (1, 0, 0): const BState('simulated:white_symmetric_sail', {'axis': 'y'}),
        (2, 0, 0): const BState('simulated:white_symmetric_sail', {'axis': 'y'}),
        // Same colour but another axis: not part of the sheet.
        (1, 1, 0): const BState('simulated:white_symmetric_sail', {'axis': 'x'}),
      };

      SymmetricSailDye.applyDye(
        state: states[(0, 0, 0)]!,
        colour: 'red',
        neighbourAt: (offset) => states[offset] ?? BState.air,
        setAt: (offset, newState) => states[offset] = newState,
      );

      expect(states[(0, 0, 0)]!.key, 'simulated:red_symmetric_sail');
      expect(states[(1, 0, 0)]!.key, 'simulated:red_symmetric_sail');
      expect(states[(1, 1, 0)]!.key, 'simulated:white_symmetric_sail');
    });

    test('the colour is read back from the block key', () {
      expect(SymmetricSailDye.colourOf('simulated:light_blue_symmetric_sail'), 'light_blue');
      expect(SymmetricSailDye.colourOf('simulated:physics_assembler'), isNull);
    });
  });

  group('HoneyGlue', () {
    test('a volume thinner than a block is rejected', () {
      final check = HoneyGlueMaxSizing.checkBounds(
        const Aabb(0, 0, 0, 0.5, 2, 2),
        maxRange: 48,
      );
      expect(check.$1, isFalse);
      expect(check.$2, HoneyGlueMaxSizing.tooSmall);
    });

    test('a volume larger than the range is rejected', () {
      final check = HoneyGlueMaxSizing.checkBounds(
        const Aabb(0, 0, 0, 60, 2, 2),
        maxRange: 48,
      );
      expect(check.$1, isFalse);
      expect(check.$2, HoneyGlueMaxSizing.tooLarge);
    });

    test('a valid volume passes and contains block centres', () {
      const box = Aabb(0, 0, 0, 3, 3, 3);
      expect(HoneyGlueMaxSizing.checkBounds(box, maxRange: 48).$1, isTrue);
      expect(HoneyGlueVolumeLogic.contains(box, (1, 1, 1)), isTrue);
      expect(HoneyGlueVolumeLogic.contains(box, (4, 1, 1)), isFalse);
    });

    test('a quarter turn swaps the horizontal extents', () {
      const box = Aabb(0, 0, 0, 2, 1, 4);
      final turned = HoneyGlueVolumeLogic.rotate(box, 1);
      expect(turned.xSize, closeTo(box.zSize, 1e-9));
      expect(turned.zSize, closeTo(box.xSize, 1e-9));
    });
  });
}
