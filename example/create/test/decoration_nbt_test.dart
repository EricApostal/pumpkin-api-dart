import 'package:create/src/api/block_state.dart';
import 'package:create/src/decoration/copycat.dart';
import 'package:test/test.dart';

void main() {
  group('copycat material NBT', () {
    // `NbtUtils.writeBlockState` / `readBlockState`: `Name` plus an optional `Properties`
    // compound of string values. The copycat stores its material in exactly this form and the
    // contraption transform reads and writes the same keys.
    test('Name and Properties round trip', () {
      const material = BState('minecraft:oak_stairs', {
        'facing': 'north',
        'half': 'bottom',
      });
      final map = materialToMap(material);

      expect(map.keys.toSet(), {'Name', 'Properties'});
      expect(map['Name'], 'minecraft:oak_stairs');
      expect((map['Properties'] as Map)['facing'], 'north');

      expect(materialFromMap(map), material);
    });

    test('a material without properties has no Properties key', () {
      final map = materialToMap(const BState('minecraft:stone'));
      expect(map.keys, ['Name']);
      expect(materialFromMap(map), const BState('minecraft:stone'));
    });

    test('a missing or malformed Name is rejected', () {
      expect(materialFromMap(const {'Properties': <String, String>{}}), isNull);
      expect(materialFromMap(const {'Name': 1}), isNull);
    });

    test('every property survives the round trip', () {
      const material = BState('create:copycat_panel', {
        'facing': 'west',
        'shape': 'inner_left',
        'waterlogged': 'false',
      });
      final back = materialFromMap(materialToMap(material));
      expect(back, material);
      expect(back!.props.length, 3);
    });

    test(
      'an empty Properties compound reads as a material without properties',
      () {
        final back = materialFromMap(const {
          'Name': 'minecraft:stone',
          'Properties': <String, Object?>{},
        });
        expect(back, const BState('minecraft:stone'));
        expect(back!.props, isEmpty);
      },
    );

    test('a non-map Properties is ignored', () {
      final back = materialFromMap(const {
        'Name': 'minecraft:stone',
        'Properties': 5,
      });
      expect(back, const BState('minecraft:stone'));
      expect(back!.props, isEmpty);
    });
  });
}
