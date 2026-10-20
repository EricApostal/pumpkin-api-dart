// Block callbacks read the state at the event position, not the event's `stateIndex`.
//
// A block callback's `stateIndex` is the index of the state within the block
// (`docs/block-callbacks.md`: `state id = baseStateId + stateIndex`), so using it as a state id
// resolves a vanilla block whose properties are missing and whose defaults silently apply. These
// tests pin the state resolution of two callbacks that were affected: the elevator contact's
// redstone (its `facing` and `powering`) and the gantry carriage's placement (`facing` and
// `axis_along_first`).
import 'package:test/test.dart';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/elevator/elevator_contact_logic.dart';
import 'package:create/src/contraptions/gantry/gantry_logic.dart';

const contact = 'create:elevator_contact';
const carriage = 'create:gantry_carriage';
const shaft = 'create:gantry_shaft';

/// An elevator contact at [pos] facing [facing], powering when [powering].
BState contactState(Direction facing, {bool powering = false}) => BState(contact, {
  'facing': facing.serializedName,
  'powering': '$powering',
  'powered': 'false',
  'calling': 'false',
});

void main() {
  group('elevator contact redstone reads the state at the position', () {
    test('a powering contact emits 15, a quiet one 0', () {
      const pos = (0, 0, 0);
      final powering = MapBlockGetter(blocks: {pos: contactState(Direction.east, powering: true)});
      final quiet = MapBlockGetter(blocks: {pos: contactState(Direction.east)});

      // `powering` is a property of the contact; the vanilla states a per-block index would
      // resolve have no such property, so the old decode always answered 0.
      expect(elevatorContactWeakPower(powering, pos, Direction.north), 15);
      expect(elevatorContactWeakPower(quiet, pos, Direction.north), 0);
    });

    test('a contact behind the reading side blocks the signal', () {
      const pos = (0, 0, 0);
      const east = (1, 0, 0);
      final level = MapBlockGetter(
        blocks: {
          pos: contactState(Direction.east, powering: true),
          east: contactState(Direction.west, powering: true),
        },
      );

      expect(elevatorContactWeakPower(level, pos, Direction.east), 0);
      expect(elevatorContactWeakPower(level, pos, Direction.north), 15);
    });

    test('wire does not connect on the side the contact faces', () {
      const pos = (0, 0, 0);
      final level = MapBlockGetter(blocks: {pos: contactState(Direction.east)});

      // `facing` comes from the state at `pos`: a contact facing east blocks the wire to the
      // west, and every other side connects. Reading a vanilla state instead would default
      // `facing` to south and refuse the north side.
      expect(elevatorContactCanConnect(level, pos, Direction.west), isFalse);
      expect(elevatorContactCanConnect(level, pos, Direction.north), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.south), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.up), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.down), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.east), isTrue);
      expect(elevatorContactCanConnect(level, pos, null), isTrue);
    });
  });

  group('gantry carriage placement reads the state at the position', () {
    test('the placed carriage keeps its key and facing', () {
      const pos = (0, 0, 0);
      const west = (-1, 0, 0);
      final placed = BState(carriage, {
        'facing': 'east',
        'axis_along_first': 'true',
      });
      final level = MapBlockGetter(
        blocks: {
          pos: placed,
          // A shaft pointing up (axis y); facing east with `axis_along_first` the carriage
          // accepts a shaft on z, so the flag has to cycle.
          west: BState(shaft, {'facing': 'up'}),
        },
      );

      final next = gantryPlacementState(level, pos);
      // A per-block `stateIndex` used as a state id would resolve a vanilla block, and the
      // carriage would be replaced by it (`facing` would fall back to north).
      expect(next.key, carriage);
      expect(next.dir('facing'), Direction.east);
      expect(next.flag('axis_along_first'), isNot(placed.flag('axis_along_first')));
    });

    test('a shaft on the facing side does not decide the axis', () {
      const pos = (0, 0, 0);
      const east = (1, 0, 0);
      final placed = BState(carriage, {
        'facing': 'east',
        'axis_along_first': 'true',
      });
      final level = MapBlockGetter(
        blocks: {
          pos: placed,
          east: BState(shaft, {'facing': 'north'}),
        },
      );

      // The shaft behind a carriage facing east is to its west; the one to its east is in front.
      expect(gantryPlacementState(level, pos), placed);
    });
  });
}
