// The pure range and direction math of the linear actuators: the piston's offset change, the
// grid snap, the disassembly rule of the movement modes, the rope length limit and the gantry
// carriage's shaft axis / pinion rules. No host, so this runs on the Dart VM.
//
// Java references (branch `port/26.3`): `LinearActuatorBlockEntity#getMovementSpeed`,
// `#getGridOffset`, `#getInterpolatedOffset`, `#tryDisassemble`, `MechanicalPistonBlockEntity
// #getMovementSpeed`, `PulleyBlockEntity#getExtensionRange`, `GantryCarriageBlock
// #getValidGantryShaftAxis`, `#cycleAxisIfNecessary`, `#canSurvive`,
// `GantryCarriageBlockEntity#getGantryPinionModifier` and `GantryContraptionEntity
// #checkPinionShaft`.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/gantry/gantry_logic.dart';
import 'package:create/src/contraptions/piston/linear_actuator_logic.dart';
import 'package:test/test.dart';

const _piston = BState('create:mechanical_piston', {
  'facing': 'north',
  'state': 'retracted',
});
const _pole = BState('create:piston_extension_pole', {'facing': 'north'});
const _head = BState('create:mechanical_piston_head', {'facing': 'north'});
const _shaft = BState('create:gantry_shaft', {
  'facing': 'east',
  'part': 'middle',
  'powered': 'false',
});

void main() {
  group('piston movement', () {
    // `pistonDirection.getAxisDirection().getStep() * (axis == Z ? -1 : 1)`: the sign that turns
    // the shaft's rotation into the extension direction.
    test('direction modifier inverts the z axis', () {
      expect(pistonDirectionModifier(Direction.north), 1);
      expect(pistonDirectionModifier(Direction.south), -1);
      expect(pistonDirectionModifier(Direction.up), 1);
      expect(pistonDirectionModifier(Direction.down), -1);
      expect(pistonDirectionModifier(Direction.east), 1);
      expect(pistonDirectionModifier(Direction.west), -1);
    });

    test('a north-facing piston retracts on positive speed', () {
      // `movementSpeed * -movementModifier` with modifier 1 -> negative.
      final speed = pistonMovementSpeed(
        speed: 256, // convertToLinear = .5, clamped to .49
        facing: Direction.north,
        offset: 2,
        extensionRange: 5,
        sequencedOffsetLimit: -1,
      );
      expect(speed, closeTo(-.49, 1e-9));
    });

    test('a south-facing piston extends on positive speed', () {
      final speed = pistonMovementSpeed(
        speed: 256,
        facing: Direction.south,
        offset: 2,
        extensionRange: 5,
        sequencedOffsetLimit: -1,
      );
      expect(speed, closeTo(.49, 1e-9));
    });

    test('the movement is clamped to the extension range and the retracted end', () {
      // At the far end: no further extension, even at full speed.
      expect(
        pistonMovementSpeed(
          speed: -256,
          facing: Direction.north,
          offset: 4.9,
          extensionRange: 5,
          sequencedOffsetLimit: -1,
        ),
        closeTo(.1, 1e-9),
      );
      // Fully retracted, retracting further: clamped to zero.
      expect(
        pistonMovementSpeed(
          speed: 256,
          facing: Direction.north,
          offset: 0,
          extensionRange: 5,
          sequencedOffsetLimit: -1,
        ),
        0,
      );
    });

    test('a sequenced distance limit caps the movement', () {
      expect(
        pistonMovementSpeed(
          speed: -256,
          facing: Direction.north,
          offset: 1,
          extensionRange: 5,
          sequencedOffsetLimit: .2,
        ),
        closeTo(.2, 1e-9),
      );
      expect(
        pistonMovementSpeed(
          speed: 256,
          facing: Direction.north,
          offset: 1,
          extensionRange: 5,
          sequencedOffsetLimit: .2,
        ),
        closeTo(-.2, 1e-9),
      );
    });

    test('the actuator speed never exceeds half a block per tick', () {
      expect(actuatorMovementSpeed(1024), .49);
      expect(actuatorMovementSpeed(-1024), -.49);
      expect(actuatorMovementSpeed(51.2), closeTo(.1, 1e-9));
    });
  });

  group('actuator offsets', () {
    test('the grid offset rounds and clamps', () {
      expect(actuatorGridOffset(0, 5), 0);
      expect(actuatorGridOffset(.49, 5), 0);
      expect(actuatorGridOffset(.5, 5), 1);
      expect(actuatorGridOffset(4.9, 5), 5);
      expect(actuatorGridOffset(9, 5), 5);
      expect(actuatorGridOffset(-3, 5), 0);
    });

    test('the interpolated offset stays inside the range', () {
      expect(actuatorInterpolatedOffset(2, .5, .4, 5), closeTo(2, 1e-9));
      expect(actuatorInterpolatedOffset(2, 1, .4, 5), closeTo(2.2, 1e-9));
      expect(actuatorInterpolatedOffset(2, 0, .4, 5), closeTo(1.8, 1e-9));
      expect(actuatorInterpolatedOffset(5, 1, .4, 5), 5);
      expect(actuatorInterpolatedOffset(0, 0, -.4, 5), closeTo(.2, 1e-9));
    });

    test('MOVE_NEVER_PLACE and an unmoved MOVE_PLACE_RETURNED wait for a speed change', () {
      expect(
        actuatorWaitsForSpeedChange(
          neverPlace: true,
          placeReturned: false,
          offset: 3,
          initialOffset: 1,
        ),
        isTrue,
      );
      expect(
        actuatorWaitsForSpeedChange(
          neverPlace: false,
          placeReturned: true,
          offset: 1.2,
          initialOffset: 1,
        ),
        isFalse,
      );
      expect(
        actuatorWaitsForSpeedChange(
          neverPlace: false,
          placeReturned: true,
          offset: 2.4,
          initialOffset: 1,
        ),
        isTrue,
      );
      expect(
        actuatorWaitsForSpeedChange(
          neverPlace: false,
          placeReturned: false,
          offset: 2.4,
          initialOffset: 1,
        ),
        isFalse,
      );
    });
  });

  group('piston extension parts', () {
    test('the piston family and its parts are recognised', () {
      expect(isPistonStateKey('create:mechanical_piston'), isTrue);
      expect(isPistonStateKey('create:sticky_mechanical_piston'), isTrue);
      expect(isPistonStateKey('create:piston_extension_pole'), isFalse);
      expect(isPistonPole(_pole), isTrue);
      expect(isPistonHead(_head), isTrue);
    });

    test('a pole matches only on its own axis', () {
      expect(pistonPoleMatchesAxis(_pole, Axis.z), isTrue);
      expect(pistonPoleMatchesAxis(_pole, Axis.x), isFalse);
      expect(pistonPoleMatchesAxis(_head, Axis.z), isFalse);
    });

    test('a stale assembly exception is cleared only with a pole behind the piston', () {
      expect(pistonHasPoleBehind(Direction.north, _pole), isTrue);
      expect(pistonHasPoleBehind(Direction.north, BState.air), isFalse);
      final crossAxis = _pole.setValue('facing', 'up');
      expect(pistonHasPoleBehind(Direction.north, crossAxis), isFalse);
    });
  });

  group('piston placement', () {
    // `DirectionalAxisKineticBlock.getStateForPlacement`: with a horizontal facing the axis along
    // first is the facing axis being z, unless a shaft above/below claims it.
    test('no neighbouring shaft keeps the facing axis', () {
      expect(
        pistonAlongFirstForPlacement(Direction.north, (_) => false),
        isTrue,
      );
      expect(
        pistonAlongFirstForPlacement(Direction.south, (_) => false),
        isTrue,
      );
      expect(
        pistonAlongFirstForPlacement(Direction.east, (_) => false),
        isFalse,
      );
      expect(
        pistonAlongFirstForPlacement(Direction.west, (_) => false),
        isFalse,
      );
    });

    test('a shaft above or below turns the axis', () {
      bool above(Direction side) => side == Direction.up;
      expect(pistonAlongFirstForPlacement(Direction.north, above), isFalse);
      expect(pistonAlongFirstForPlacement(Direction.east, above), isTrue);
      bool below(Direction side) => side == Direction.down;
      expect(pistonAlongFirstForPlacement(Direction.south, below), isFalse);
      // Sideways shafts do not decide it (`prefersConnectionTo(..., false)`).
      bool east(Direction side) => side == Direction.east;
      expect(pistonAlongFirstForPlacement(Direction.north, east), isTrue);
    });

    test('a vertical facing is left to the host default', () {
      expect(
        pistonAlongFirstForPlacement(Direction.up, (_) => false),
        isTrue,
      );
    });
  });

  group('pulley range', () {
    test('the rope stops at the config limit or the world floor', () {
      // y=100, minY=-64: 163 blocks available, the config allows 256.
      expect(
        pulleyExtensionRange(y: 100, minY: -64, maxRopeLength: 256),
        163,
      );
      // The config is the tighter limit.
      expect(pulleyExtensionRange(y: 100, minY: -64, maxRopeLength: 32), 32);
      // The pulley sits on the floor: no rope at all.
      expect(pulleyExtensionRange(y: -63, minY: -64, maxRopeLength: 256), 0);
    });
  });

  group('gantry carriage', () {
    test('the valid shaft axis is the one left over', () {
      // Facing north (z), axis_along_first=true -> rotation axis x; the shaft rides y.
      const facingNorth = BState('create:gantry_carriage', {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      expect(getValidGantryShaftAxis(facingNorth), Axis.y);

      // Facing up, along first -> rotation x, so the shaft rides z.
      const facingUp = BState('create:gantry_carriage', {
        'facing': 'up',
        'axis_along_first': 'true',
      });
      expect(getValidGantryShaftAxis(facingUp), Axis.z);

      expect(getValidGantryPinionAxis(facingUp, Axis.z), Axis.x);
    });

    test('the carriage survives only on a shaft behind it, on another axis', () {
      const carriage = BState('create:gantry_carriage', {'facing': 'north'});
      expect(gantryCarriageCanSurvive(carriage, _shaft), isTrue);
      // The shaft runs along the facing axis: invalid.
      final along = _shaft.setValue('facing', 'north');
      expect(gantryCarriageCanSurvive(carriage, along), isFalse);
      expect(gantryCarriageCanSurvive(carriage, BState.air), isFalse);
    });

    test('placing next to a shaft cycles axis_along_first to match it', () {
      const carriage = BState('create:gantry_carriage', {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      // Facing north: rotation x, so the valid shaft axis is y. A vertical shaft fits.
      final vertical = _shaft.setValue('facing', 'up');
      expect(
        cycleGantryAxisIfNecessary(carriage, Direction.south, vertical),
        carriage,
      );
      // An east/west shaft does not: the axis is cycled until it matches.
      final cycled = cycleGantryAxisIfNecessary(
        carriage,
        Direction.south,
        _shaft,
      );
      expect(cycled.flag('axis_along_first'), isFalse);
      expect(getValidGantryShaftAxis(cycled), Axis.x);
      // A non-shaft neighbour leaves the state alone.
      expect(
        cycleGantryAxisIfNecessary(carriage, Direction.south, BState.air),
        carriage,
      );
    });

    test('the pinion modifier flips for the shaft directions of the reference', () {
      // Java: Y shaft with the pinion facing north/east negates, X with down/south, Z with
      // up/west.
      expect(getGantryPinionModifier(Direction.up, Direction.north), -1);
      expect(getGantryPinionModifier(Direction.up, Direction.south), 1);
      expect(getGantryPinionModifier(Direction.east, Direction.down), -1);
      expect(getGantryPinionModifier(Direction.east, Direction.up), 1);
      expect(getGantryPinionModifier(Direction.south, Direction.up), -1);
      expect(getGantryPinionModifier(Direction.south, Direction.down), 1);
    });

    test('the gantry moves with the shaft and reverses on negative speed', () {
      expect(gantryPinionMovementDirection(Direction.east, .2), Direction.east);
      expect(
        gantryPinionMovementDirection(Direction.east, -.2),
        Direction.west,
      );
    });

    test('crossing into the next block along the shaft is detected', () {
      // Moving east: floor(4.5) + .5 = 4.5 < 4.7, so the gantry enters the next block.
      expect(gantryCrossedShaftEnd(4.5, 4.7, .2, 1), isTrue);
      // 4.3 -> 4.4 stays inside the block (4.5 < 4.4 is false).
      expect(gantryCrossedShaftEnd(4.3, 4.4, .2, 1), isFalse);
      // Moving west, the reference expression is never true.
      expect(gantryCrossedShaftEnd(4.4, 4.2, -.2, -1), isFalse);
      expect(gantryCrossedShaftEnd(4.5, 4.3, -.2, -1), isFalse);
    });
  });

  test('the piston block state defaults are the reference ones', () {
    // The manifest default: retracted, facing north, axis along first.
    expect(_piston['state'], 'retracted');
    expect(_piston.dir('facing'), Direction.north);
  });
}
