import 'package:create/src/equipment/blocks/shapes.dart';
import 'package:create/src/equipment/model/dir.dart';
import 'package:test/test.dart';

void main() {
  test('horizontal rotation of boxes', () {
    final m = forHorizontal(toolboxBoxes);
    final n = m[Dir.north]!.single;
    expect((n.minX, n.minZ, n.maxX, n.maxZ), (1 / 16, 4 / 16, 15 / 16, 12 / 16));
    final e = m[Dir.east]!.single;
    // 14 wide in x became 8 wide in x and 14 in z
    expect(e.maxX - e.minX, closeTo(8 / 16, 1e-9));
    expect(e.maxZ - e.minZ, closeTo(14 / 16, 1e-9));
    final s = m[Dir.south]!.single;
    expect(s.minX, closeTo(1 / 16, 1e-9));
  });

  test('a south based shape faces south unrotated', () {
    final m = forHorizontal([(3, 1, 0, 13, 15, 1)], base: Dir.south);
    expect(m[Dir.south]!.single.minZ, 0);
    expect(m[Dir.north]!.single.maxZ, closeTo(1, 1e-9));
  });

  test('rule counts', () {
    expect(bellRules().length, 16);
    expect(clipboardRules().length, 12);
  });
}
