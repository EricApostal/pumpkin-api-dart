import 'package:create/src/equipment/model/dir.dart';
import 'package:create/src/equipment/zapper/shaper_model.dart';
import 'package:test/test.dart';

class _Grid implements ShaperWorld {
  final Map<P3, String> blocks = {};
  final bool Function(P3) solidFn;
  _Grid(this.solidFn);

  @override
  ShaperCell cell(P3 pos) {
    final b = blocks[pos] ?? (solidFn(pos) ? 'stone' : 'air');
    return ShaperCell(state: b, block: b, replaceable: b == 'air', hasSolidSide: (_) => b != 'air');
  }

  @override
  Future<void> setAir(P3 pos) async => blocks[pos] = 'air';

  @override
  Future<void> place(P3 pos, Object? painted, Object? data) async => blocks[pos] = painted as String;

  @override
  Future<void> setState(P3 pos, Object state) async => blocks[pos] = state as String;

  @override
  Object fluidLegacyState(P3 pos) => 'air';
}

void main() {
  group('brushes', () {
    test('cuboid centers on the target', () {
      final b = CuboidBrush()..set(3, 3, 3);
      expect(b.includedPositions!.length, 27);
      expect(b.includedPositions!.first, (-1, -1, -1));
      b.set(2, 1, 1);
      expect(b.includedPositions!.toSet(), {(0, 0, 0), (1, 0, 0)});
      expect(b.getMin(0), 1);
      expect(b.getMax(0), 32);
    });

    test('sphere sizes', () {
      final b = SphereBrush()..set(0, 0, 0);
      expect(b.includedPositions!.length, 1);
      b.set(1, 0, 0);
      expect(b.includedPositions!.length, 19);
      b.set(2, 0, 0);
      expect(b.includedPositions!.length, 81);
    });

    test('cylinder', () {
      final b = CylinderBrush()..set(1, 1, 0);
      expect(b.includedPositions!.length, 9);
      b.set(1, 3, 0);
      expect(b.includedPositions!.length, 27);
      expect(b.includedPositions!.map((p) => p.$2).toSet(), {-1, 0, 1});
      b.set(9, 1, 0);
      expect(b.includedPositions, isNull);
    });

    test('offsets by placement option', () {
      final b = CuboidBrush()..set(3, 3, 3);
      expect(b.getOffset((0, 0, 0), Dir.up, PlacementOptions.merged), (0, 0, 0));
      expect(b.getOffset((0, 0, 0), Dir.up, PlacementOptions.attached), (0, 2, 0));
      expect(b.getOffset((0, 0, 0), Dir.down, PlacementOptions.attached), (0, -2, 0));
      expect(b.getOffset((0, 0, 0), Dir.up, PlacementOptions.inserted), (0, -1, 0));
      final s = SphereBrush()..set(2, 0, 0);
      expect(s.getOffset((0, 0, 0), Dir.north, PlacementOptions.attached), (0, 0, -3));
      expect(s.getOffset((0, 0, 0), Dir.north, PlacementOptions.inserted), (0, 0, 2));
    });
  });

  group('patterns', () {
    test('checkered', () {
      final l = <P3>[(0, 0, 0), (1, 0, 0), (1, 1, 0), (2, 0, 0)];
      PlacementPatterns.apply(l, PlacementPatterns.checkered, () => true);
      expect(l, [(1, 0, 0)]);
      final m = <P3>[(0, 0, 0), (1, 0, 0)];
      PlacementPatterns.apply(m, PlacementPatterns.inverseCheckered, () => true);
      expect(m, [(0, 0, 0)]);
    });

    test('chance patterns evaluate the random like Java', () {
      final calls = <int>[];
      var n = 0;
      bool r() {
        calls.add(n++);
        return false;
      }

      final l = <P3>[(0, 0, 0), (1, 0, 0)];
      PlacementPatterns.apply(l, PlacementPatterns.chance25, r);
      // chance25 = nextBoolean() || nextBoolean(): false,false -> keep both, 4 calls
      expect(l.length, 2);
      expect(calls.length, 4);
      final k = <P3>[(0, 0, 0)];
      PlacementPatterns.apply(k, PlacementPatterns.chance75, () => false); // false && .. -> not removed
      expect(k.length, 1);
      final z = <P3>[(0, 0, 0)];
      PlacementPatterns.apply(z, PlacementPatterns.chance50, () => true);
      expect(z, isEmpty);
    });
  });

  group('tools', () {
    test('fill only replaceable, replace only non replaceable', () async {
      final w = _Grid((p) => p.$2 <= 0);
      await TerrainTools.fill.run(w, [(0, 0, 0), (0, 1, 0)], Dir.up, 'gold', null);
      expect(w.blocks[(0, 0, 0)], isNull);
      expect(w.blocks[(0, 1, 0)], 'gold');
      await TerrainTools.replace.run(w, [(1, 0, 0), (1, 1, 0)], Dir.up, 'gold', null);
      expect(w.blocks[(1, 0, 0)], 'gold');
      expect(w.blocks[(1, 1, 0)], isNull);
      await TerrainTools.clear.run(w, [(2, 0, 0)], Dir.up, null, null);
      expect(w.blocks[(2, 0, 0)], 'air');
    });

    test('overlay places on top of solid ground', () async {
      final w = _Grid((p) => p.$2 <= 0);
      await TerrainTools.overlay.run(w, [(0, 0, 0), (0, 5, 0)], Dir.up, 'moss', null);
      expect(w.blocks[(0, 1, 0)], 'moss');
      expect(w.blocks.containsKey((0, 6, 0)), isFalse);
    });
  });

  group('dynamic brush', () {
    test('surface replace flood fills the connected same block', () {
      final w = _Grid((p) => p.$2 <= 0 && p.$1.abs() <= 3 && p.$3.abs() <= 3);
      final b = DynamicBrush(true)..set(2, 1, 1);
      final out = <P3>[];
      b.addToGlobalPositions(w, (0, 0, 0), Dir.up, out, TerrainTools.replace);
      expect(out, isNotEmpty);
      expect(out.every((p) => p.$2 == 0), isTrue);
      // range 2: closerThan(start, 2) -> squared distance < 4
      expect(out.every((p) => p.$1 * p.$1 + p.$3 * p.$3 < 4), isTrue);
    });
  });

  group('flatten', () {
    test('kernel keeps a flat field flat', () {
      final out = FlattenTool.applyKernel(List.generate(5, (_) => List.filled(5, 10)));
      expect(out.every((r) => r.every((v) => v == 10)), isTrue);
    });

    test('flatten smooths a spike', () async {
      // ground at y=0 everywhere in a 7x7 area, a 3 high spike at the center
      bool solid(P3 p) => p.$2 <= 0 || (p.$1 == 3 && p.$3 == 3 && p.$2 <= 3);
      final w = _Grid(solid);
      final targets = <P3>[
        for (var x = 0; x < 7; x++)
          for (var z = 0; z < 7; z++) (x, x == 3 && z == 3 ? 3 : 0, z),
      ];
      await FlattenTool.apply(w, targets, Dir.up);
      // the spike top got lowered (the surface block above it was removed)
      final top = w.cell((3, 3, 3));
      expect(top.state == 'air' || w.blocks[(3, 3, 3)] == 'air', isTrue);
    });
  });
}
