// Regression test for block orientation on placement: a block placed while looking
// along each of the four cardinal directions gets the state the client's Java
// `getStateForPlacement` picks.
//
// The expectations are a transcription of the Java, not a copy of the plugin's
// answer, so the test fails if either side drifts.
//
//   `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` (the physics
//   assembler and the throttle lever), from the bytecode of
//   `simulated-neoforge-26.3-1.3.2.jar`, read with `javap -c`:
//
//     for (Direction d : context.getNearestLookingDirections()) {
//         BlockState s;
//         if (d.getAxis() == Direction.Axis.Y) {
//             s = defaultBlockState()
//                 .setValue(FACE, d == Direction.UP ? AttachFace.CEILING : AttachFace.FLOOR)
//                 .setValue(FACING, context.getHorizontalDirection());
//         } else {
//             s = defaultBlockState().setValue(FACE, AttachFace.WALL)
//                 .setValue(FACING, d.getOpposite());
//         }
//         if (s.canSurvive(context.getLevel(), context.getClickedPos())) return s;
//     }
//     return null;
//
//   `SteeringWheelBlock.getStateForPlacement`:
//
//     boolean onFloor = switch (context.getClickedFace()) {
//         case UP -> true;
//         case DOWN -> false;
//         default -> orderedLookDirections().filter(isVertical).findFirst().get() == DOWN;
//     };
//     Direction facing = orderedLookDirections().filter(isHorizontal).findFirst().get();
//     return withWater(defaultBlockState(), context)
//         .setValue(FACING, facing.getOpposite()).setValue(ON_FLOOR, onFloor);
//
// `getNearestLookingDirections()` is the player's directions ordered by nearest look,
// with the opposite of the clicked face moved to the front (unless the clicked block
// was replaced). For the placements below:
//
//   * a click on the wall in front (the side face toward the player): the front is
//     the direction from the placed block to the clicked one, which is horizontal —
//     FACE = wall, FACING = its opposite, i.e. the plate faces the player;
//   * a click on the top face while looking level: the front is DOWN — FACE = floor,
//     FACING = `getHorizontalDirection()`, the way the player looks;
//   * a click on the bottom face: the front is UP — FACE = ceiling, FACING = the look.
//
// Pure: no host imports, the test runs on the plain Dart VM.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:simulated/src/content/blocks/sim_placement.dart';
import 'package:test/test.dart';

/// `Entity.getViewVector(1.0F)` for a yaw and a pitch in degrees — what the host's
/// `Player.lookDirection` is (`directionFromRotation`).
(double, double, double) _view(double yawDegrees, double pitchDegrees) {
  final y = yawDegrees * math.pi / 180, p = pitchDegrees * math.pi / 180;
  final cp = math.cos(p);
  return (-math.sin(y) * cp, -math.sin(p), math.cos(y) * cp);
}

/// `Player.getDirection()` of a look: `Direction.fromYRot(yaw)`.
Direction _horizontal((double, double, double) view) =>
    Direction.fromYRot(math.atan2(-view.$1, view.$3) * 180 / math.pi);

/// The four cardinal look directions with Minecraft's yaw: 0 looks south, 90 west,
/// 180 north, 270 east.
const Map<Direction, double> _cardinals = {
  Direction.north: 180.0,
  Direction.east: 270.0,
  Direction.south: 0.0,
  Direction.west: 90.0,
};

(int, int, int) _step((int, int, int) pos, Direction d) =>
    (pos.$1 + d.stepX, pos.$2 + d.stepY, pos.$3 + d.stepZ);

/// One placement: [placed] is where the block goes, [clicked] is the block the player
/// clicked, and the clicked block is the only block in the world (which is what the
/// player places against).
final class _Placement {
  final (int, int, int) placed;
  final (int, int, int) clicked;
  final (double, double, double) view;
  final Direction clickedFace;

  const _Placement(this.placed, this.clicked, this.view, this.clickedFace);

  /// The state a face-attached block gets here (`null` when nothing supports it).
  BState? faceAttached(String key) => faceAttachedStateForPlacement(
    defaultState: BState(key, const {'facing': 'north', 'face': 'wall'}),
    nearestLooking: nearestLookingDirections(
      orderedByNearest: Direction.orderedByNearest(view.$1, view.$2, view.$3),
      clickedFace: clickedFace,
      replacingClickedOnBlock: false,
    ),
    horizontalDirection: _horizontal(view),
    // `canSurvive`: the support of the candidate kind of attachment has to be
    // sturdy, and the clicked block is the only block there is.
    canSurvive: (connected) => _step(placed, connected.opposite) == clicked,
  );

  /// The state a steering wheel gets here.
  BState steeringWheel(String key) => steeringWheelStateForPlacement(
    defaultState: BState(key, const {'facing': 'north', 'on_floor': 'true', 'waterlogged': 'false'}),
    view: view,
    clickedFace: clickedFace,
  );
}

void main() {
  const assembler = 'simulated:physics_assembler';

  group('a face-attached block (the physics assembler, the throttle lever)', () {
    for (final entry in _cardinals.entries) {
      final looking = entry.key;
      final view = _view(entry.value, 0);
      const placed = (0, 0, 0);
      // The clicked block is in front of the player, at the same level.
      final inFront = _step(placed, looking);

      test('looking ${looking.serializedName}: the wall in front gives a wall plate', () {
        // The clicked face is the one toward the player, so the block goes into the
        // position between the player and the clicked block.
        final state = _Placement(_step(inFront, looking.opposite), inFront, view, looking.opposite)
            .faceAttached(assembler);
        expect(state, isNotNull);
        expect(state!['face'], 'wall');
        expect(state.dir('facing'), looking.opposite,
            reason: 'FACING is the opposite of the direction the block attached to, so the plate faces the player');
      });

      test('looking ${looking.serializedName}: a click on the top face gives a floor plate', () {
        // The block goes on top of the clicked block (`clickedPos.relative(UP)`).
        final state = _Placement(_step(inFront, Direction.up), inFront, view, Direction.up).faceAttached(assembler);
        expect(state, isNotNull);
        expect(state!['face'], 'floor');
        expect(state.dir('facing'), looking,
            reason: 'FACE = floor keeps `getHorizontalDirection()` as FACING');
      });

      test('looking ${looking.serializedName}: a click on the bottom face gives a ceiling plate', () {
        final state = _Placement(_step(inFront, Direction.down), inFront, view, Direction.down).faceAttached(assembler);
        expect(state, isNotNull);
        expect(state!['face'], 'ceiling');
        expect(state.dir('facing'), looking);
      });
    }

    test('a top click with no floor below falls back to the wall beside it', () {
      // Looking north at a block whose top was clicked, but the placement has no
      // floor under it (the clicked block is north of the placement, not below it):
      // `canSurvive` refuses FACE = floor, the next looking direction is the
      // horizontal one, and the plate becomes a wall plate on the clicked block.
      final state = _Placement((0, 0, 0), _step((0, 0, 0), Direction.north), _view(180, 0), Direction.up)
          .faceAttached(assembler);
      expect(state, isNotNull);
      expect(state!['face'], 'wall');
      expect(state.dir('facing'), Direction.south);
    });

    test('no support at all is no placement', () {
      expect(
        _Placement((0, 0, 0), (40, 40, 40), _view(180, 0), Direction.up).faceAttached(assembler),
        isNull,
      );
    });
  });

  group('the steering wheel', () {
    for (final entry in _cardinals.entries) {
      final looking = entry.key;
      final view = _view(entry.value, 0);
      const placed = (0, 0, 0);
      final inFront = _step(placed, looking);

      test('looking ${looking.serializedName}: the wheel faces the player and stands on the floor', () {
        // A wall click leaves `on_floor` to the first vertical look direction, which
        // at pitch 0 is DOWN (a level look stands the wheel on the floor).
        final state = _Placement(placed, inFront, view, looking.opposite).steeringWheel('simulated:steering_wheel');
        expect(state.dir('facing'), looking.opposite);
        expect(state.flag('on_floor'), isTrue);
      });

      test('looking ${looking.serializedName}: a click on the bottom face puts the wheel on the ceiling', () {
        final state = _Placement(placed, inFront, view, Direction.down).steeringWheel('simulated:steering_wheel');
        expect(state.dir('facing'), looking.opposite);
        expect(state.flag('on_floor'), isFalse);
      });
    }

    test('looking up does not stand the wheel on the floor', () {
      // Pitch -90: the first vertical look direction is UP, so a wall click gives
      // `on_floor = false`; only a click on a top face forces it.
      final state = _Placement((0, 0, 0), _step((0, 0, 0), Direction.north), _view(180, -90), Direction.south)
          .steeringWheel('simulated:steering_wheel');
      expect(state.dir('facing'), Direction.south);
      expect(state.flag('on_floor'), isFalse);
    });
  });

  group('getNearestLookingDirections', () {
    test('moves the opposite of the clicked face to the front', () {
      final ordered = Direction.orderedByNearest(0, 0, 1); // looking south
      final adjusted = nearestLookingDirections(
        orderedByNearest: ordered,
        clickedFace: Direction.down,
        replacingClickedOnBlock: false,
      );
      expect(adjusted.first, Direction.up);
      expect(adjusted.sublist(1), ordered.where((d) => d != Direction.up));
    });

    test('keeps the order when the clicked block was replaced', () {
      final ordered = Direction.orderedByNearest(0, 0, 1);
      expect(
        nearestLookingDirections(
          orderedByNearest: ordered,
          clickedFace: Direction.down,
          replacingClickedOnBlock: true,
        ),
        ordered,
      );
    });

    test('a face already in front is left alone', () {
      final ordered = Direction.orderedByNearest(0, 0, 1);
      expect(
        nearestLookingDirections(
          orderedByNearest: ordered,
          clickedFace: Direction.north,
          replacingClickedOnBlock: false,
        ),
        ordered,
      );
    });
  });
}