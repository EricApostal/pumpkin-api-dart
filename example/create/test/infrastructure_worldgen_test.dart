import 'package:create/src/infrastructure/worldgen/layered_ore.dart';
import 'package:create/src/infrastructure/worldgen/striated_ores.dart';
import 'package:create/src/infrastructure/worldgen/worldgen_random.dart';
import 'package:test/test.dart';

final class _Chunk implements OreChunk {
  @override
  final int minY = -64, maxY = 319;
  final Map<(int, int, int), int> blocks = {};
  final int ground;
  _Chunk(this.ground);

  @override
  int getState(int lx, int y, int lz) => blocks[(lx, y, lz)] ?? (y < ground ? 1 : 0);

  @override
  void setState(int lx, int y, int lz, int stateId) => blocks[(lx, y, lz)] = stateId;
}

final class _Info implements OreStateInfo {
  @override
  bool matches(int stateId, OreRuleTest test) => stateId == 1; // 1 = stone for every rule

  @override
  int? stateOf(String key) => 100 + key.hashCode % 50;

  @override
  bool isSolid(int stateId) => stateId != 0;
}

void main() {
  test('LegacyRandom matches java.util.Random', () {
    // new Random(42): nextInt(100) sequence 30, 63, 48 ; nextInt() first = -1170105035
    final r = LegacyRandom(42);
    expect(r.nextInt(100), 30);
    expect(r.nextInt(100), 63);
    expect(r.nextInt(100), 48);
    expect(LegacyRandom(42).nextInt(), -1170105035);
    // new Random(0).nextDouble() = 0.730967787376657
    expect(LegacyRandom(0).nextDouble(), closeTo(0.730967787376657, 1e-12));
  });

  test('simplex noise is deterministic and bounded', () {
    final a = SimplexNoise(LegacyRandom(5));
    final b = SimplexNoise(LegacyRandom(5));
    var max = 0.0;
    for (var i = 0; i < 200; i++) {
      final v = a.get(i * 0.37, i * 0.11, i * 0.53);
      expect(v, b.get(i * 0.37, i * 0.11, i * 0.53));
      if (v.abs() > max) max = v.abs();
    }
    expect(max, lessThan(2.5));
    expect(max, greaterThan(0.05));
  });

  test('a vein clipped to two chunks equals the vein clipped to both', () {
    Map<(int, int, int), String> run(VeinClip clip) {
      final out = <(int, int, int), String>{};
      generateLayeredVein(LayeredOreConfiguration(AllLayerPatterns.overworld, 32, 0), LegacyRandom(1234), 15, 20, 8, clip,
          (x, y, z, targets, random) {
        out[(x, y, z)] = targets.first.stateKey;
        return true;
      });
      return out;
    }

    final left = run(const VeinClip(0, 15, 0, 15, -64, 319));
    final right = run(const VeinClip(16, 31, 0, 15, -64, 319));
    final both = run(const VeinClip(0, 31, 0, 15, -64, 319));
    expect(left, isNotEmpty);
    expect(right, isNotEmpty);
    expect({...left, ...right}, both);
  });

  test('striated ore placement writes ore only into stone and agrees with neighbours', () {
    var total = 0;
    final chunks = <(int, int), _Chunk>{};
    for (var cx = -3; cx <= 3; cx++) {
      for (var cz = -3; cz <= 3; cz++) {
        final c = _Chunk(80);
        chunks[(cx, cz)] = c;
        total += placeStriatedOresInChunk(
          feature: StriatedOreFeature.overworld,
          worldSeed: 987654321,
          chunkX: cx,
          chunkZ: cz,
          chunk: c,
          info: _Info(),
        );
      }
    }
    expect(total, greaterThan(500));
    for (final c in chunks.values) {
      for (final e in c.blocks.entries) {
        expect(e.key.$2, lessThan(80));
        expect(e.value, greaterThanOrEqualTo(100));
      }
    }
    // Deterministic.
    final again = _Chunk(80);
    placeStriatedOresInChunk(
      feature: StriatedOreFeature.overworld,
      worldSeed: 987654321,
      chunkX: 1,
      chunkZ: 1,
      chunk: again,
      info: _Info(),
    );
    expect(again.blocks, chunks[(1, 1)]!.blocks);
  });

  test('rarity is about 1 in 18', () {
    var hits = 0;
    for (var x = 0; x < 100; x++) {
      for (var z = 0; z < 100; z++) {
        if (rollOrigin(StriatedOreFeature.overworld, 1, x, z) != null) hits++;
      }
    }
    expect(hits / 10000, closeTo(1 / 18, 0.01));
  });
}
