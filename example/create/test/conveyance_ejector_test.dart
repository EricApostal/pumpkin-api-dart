import 'package:test/test.dart';

import 'package:create/src/common/direction.dart';
import 'package:create/src/common/vec_helper.dart';
import 'package:create/src/conveyance/transport/depot/entity_launcher.dart';

void main() {
  group('EntityLauncher', () {
    test('motionFor rotates the trajectory like applyMotion', () {
      final launcher = EntityLauncher(5, 2);
      for (final facing in Direction.planeHorizontal) {
        // At t = 0 the trajectory velocity is (0, _yMotion, _xMotion); `motionFor` rotates it
        // around Y by the facing's horizontal angle and applies Java's 0.91 / 0.98 drag factors.
        final expected = VecHelper.rotate(
          (0.0, launcher.dy(0), launcher.dx(0)),
          AngleHelper.horizontalAngle(facing),
          Axis.y,
        );
        final actual = launcher.motionFor(facing);
        expect(
          actual.$1,
          closeTo(expected.$1 * .91, 1e-9),
          reason: '$facing x',
        );
        expect(
          actual.$2,
          closeTo(expected.$2 * .98, 1e-9),
          reason: '$facing y',
        );
        expect(
          actual.$3,
          closeTo(expected.$3 * .91, 1e-9),
          reason: '$facing z',
        );
      }
    });
  });
}
