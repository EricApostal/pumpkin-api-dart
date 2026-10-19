import 'package:create/src/equipment/bell/bell_nbt.dart';
import 'package:create/src/equipment/model/dir.dart';
import 'package:test/test.dart';

void main() {
  test('Ringing names round trip like Java enum names', () {
    for (final d in Dir.values) {
      expect(
        ringDirectionFromNbtName(ringDirectionNbtName(d)),
        d,
        reason: d.name,
      );
    }
    expect(ringDirectionNbtName(Dir.north), 'NORTH');
    expect(ringDirectionNbtName(Dir.down), 'DOWN');
  });

  test('unknown or missing Ringing names fall back to down', () {
    // `readEnum` compares `e.name().equals(name)` case-sensitively.
    expect(ringDirectionFromNbtName('SIDEWAYS'), Dir.down);
    expect(ringDirectionFromNbtName(''), Dir.down);
    expect(ringDirectionFromNbtName('north'), Dir.down);
    expect(ringDirectionFromNbtName('NORTH'), Dir.north);
  });
}
