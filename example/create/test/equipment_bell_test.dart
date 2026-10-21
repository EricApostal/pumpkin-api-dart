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
    expect(ringDirectionFromNbtName('SIDEWAYS'), Dir.down);
    expect(ringDirectionFromNbtName(''), Dir.down);
    // The port also accepts the lower-case spelling of an older save, which
    // Java's case-sensitive `e.name().equals(name)` would drop to `down`.
    expect(ringDirectionFromNbtName('north'), Dir.north);
    expect(ringDirectionFromNbtName('NORTH'), Dir.north);
  });
}
