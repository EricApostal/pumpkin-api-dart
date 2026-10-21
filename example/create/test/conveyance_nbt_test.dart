// Pure parity tests for the NBT forms the conveyance block entities write. The
// block entities themselves import the host bindings and cannot run on the VM,
// so the enum-name and flap/side list encodings live in `nbt_names.dart` and are
// covered here. Java references: `BrassTunnelBlockEntity.readDirection` /
// `writeFlapsAndSides`, `EjectorBlockEntity.State`.
import 'package:create/src/common/direction.dart';
import 'package:create/src/conveyance/nbt_names.dart';
import 'package:create/src/processing/arm/arm_model.dart' show ArmPhase;
import 'package:test/test.dart';

void main() {
  group('enum names', () {
    test('Java writes Enum.name(), the upper-case constant', () {
      expect(enumNbtName('charged'), 'CHARGED');
      expect(enumNbtName('retracting'), 'RETRACTING');
      expect(directionNbtName(Direction.north), 'NORTH');
    });

    test('an unknown constant has no match', () {
      expect(enumByNameIgnoreCase('SIDEWAYS', Direction.values), isNull);
    });

    test(
      'names are matched case insensitively, for older lower-case saves',
      () {
        expect(enumByNameIgnoreCase('NORTH', Direction.values), Direction.north);
        expect(enumByNameIgnoreCase('north', Direction.values), Direction.north);
      },
    );
  });

  // The test that would have caught the train crash: an enum value is written as
  // its Java constant name and resolved the way Java's `readEnum` resolves it, so
  // the intended constant comes back instead of the first one.
  group('readEnum semantics', () {
    test('resolves the Java constant name, not the first constant', () {
      expect(enumFromNbtName('NORTH', Direction.values), Direction.north);
      expect(
        enumFromNbtName('NORTH', Direction.values),
        isNot(Direction.values.first),
      );
    });

    test('an unknown or missing name is the first constant, as Java', () {
      expect(enumFromNbtName('sideways', Direction.values), Direction.down);
      expect(enumFromNbtName(null, Direction.values), Direction.down);
    });

    test('matches case insensitively, for older lower-case saves', () {
      expect(enumFromNbtName('north', Direction.values), Direction.north);
    });

    test('nameOf carries an enum whose Dart identifier differs', () {
      expect(
        enumFromNbtName(
          'SEARCH_OUTPUTS',
          ArmPhase.values,
          nameOf: (p) => p.javaName,
        ),
        ArmPhase.searchOutputs,
      );
      expect(
        enumFromNbtName(
          'SEARCH_OUTPUTS',
          ArmPhase.values,
          nameOf: (p) => p.javaName,
        ),
        isNot(ArmPhase.values.first),
      );
    });

    test('enumByNameIgnoreCase is null when nothing matches', () {
      expect(enumByNameIgnoreCase('sideways', Direction.values), isNull);
      expect(enumByNameIgnoreCase(null, Direction.values), isNull);
      expect(enumByNameIgnoreCase('EAST', Direction.values), Direction.east);
    });
  });

  group('StackEnteredFrom', () {
    test('every direction round trips through the NBT name', () {
      for (final d in Direction.values) {
        expect(directionFromNbtName(directionNbtName(d)), d);
      }
    });

    test('a lower-case name from an older Dart build is still read', () {
      expect(directionFromNbtName('north'), Direction.north);
      expect(directionFromNbtName('WEST'), Direction.west);
    });

    test(
      'an unknown name falls back to the first constant, as readDirection',
      () {
        expect(directionFromNbtName('sideways'), Direction.down);
      },
    );
  });

  group('Flaps / Sides', () {
    test('the values are get3DDataValue in set order', () {
      final dirs = <Direction>{Direction.north, Direction.east};
      expect(directionValues(dirs), [2, 5]);
      expect(directionsFromValues(directionValues(dirs)), dirs);
    });

    test('reading clamps unknown values like Direction.from3DDataValue', () {
      expect(
        directionsFromValues([0, 1, 2, 3, 4, 5]),
        Direction.values.toSet(),
      );
      expect(directionsFromValues([9]), {Direction.from3DDataValue(9)});
    });

    test('an empty list reads as no sides', () {
      expect(directionsFromValues(const []), isEmpty);
    });
  });
}
