// Random numbers and noise for world generation (pure): java.util.Random compatible
// `LegacyRandomSource` and Minecraft's `SimplexNoise` (26.3), so the layered ores have
// the same shape distribution as the Java mod.
import 'dart:math' as math;
import 'dart:typed_data';

final Float32List _f32 = Float32List(1);

double _float(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// `net.minecraft.world.level.levelgen.LegacyRandomSource` (a 48 bit LCG).
final class LegacyRandom {
  static const int _mask = 0xFFFFFFFFFFFF;
  static const int _multiplier = 0x5DEECE66D;
  static const int _increment = 0xB;

  int _seed = 0;

  LegacyRandom(int seed) {
    setSeed(seed);
  }

  void setSeed(int seed) => _seed = (seed ^ _multiplier) & _mask;

  /// `next(bits)`: the next `bits` random bits as a signed 32 bit value.
  int next(int bits) {
    _seed = (_seed * _multiplier + _increment) & _mask;
    final v = _seed >> (48 - bits);
    return (v & 0xFFFFFFFF).toSigned(32);
  }

  int nextInt([int? bound]) {
    if (bound == null) return next(32);
    if (bound <= 0) throw ArgumentError('bound must be positive');
    if ((bound & (bound - 1)) == 0) return (bound * next(31)) >> 31;
    int sample, mod;
    do {
      sample = next(31);
      mod = sample % bound;
    } while ((sample - mod + (bound - 1)).toSigned(32) < 0);
    return mod;
  }

  /// `nextIntBetweenInclusive(lo, hi)`.
  int nextIntBetweenInclusive(int lo, int hi) => nextInt(hi - lo + 1) + lo;

  int nextLong() => ((next(32) << 32) + next(32));

  bool nextBoolean() => next(1) != 0;

  /// A float in `[0, 1)`.
  double nextFloat() => next(24) * 5.9604645E-8;

  /// A double in `[0, 1)`.
  double nextDouble() => ((next(26) << 27) + next(27)) * 1.1102230246251565E-16;

  /// `Mth.randomBetween(random, min, max)`.
  double randomBetween(double min, double max) => _float(nextFloat() * (max - min) + min);
}

/// The 3D seed hash of `Mth.getSeed(x, y, z)`.
int mthGetSeed(int x, int y, int z) {
  var seed = ((x * 3129871) ^ (z * 116129781) ^ y);
  seed = seed * seed * 42317861 + seed * 11;
  return seed >> 16;
}

/// Mixes several integers into one seed (SplitMix64 finaliser), stable across runs and platforms.
int mixSeed(int a, [int b = 0, int c = 0, int d = 0]) {
  var h = 0x9E3779B97F4A7C15;
  for (final v in [a, b, c, d]) {
    h ^= v + 0x9E3779B97F4A7C15 + (h << 6) + (h >> 2);
    h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9;
    h = (h ^ (h >>> 27)) * 0x94D049BB133111EB;
    h = h ^ (h >>> 31);
  }
  return h;
}

/// `SimplexNoise` (3D).
final class SimplexNoise {
  static const List<List<int>> _gradient = [
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
    [1, 1, 0], [0, -1, 1], [-1, 1, 0], [0, -1, -1],
  ];

  final Uint8List _perms = Uint8List(256);
  late final double offsetX, offsetY, offsetZ;

  SimplexNoise(LegacyRandom random) {
    offsetX = random.nextDouble() * 256.0;
    offsetY = random.nextDouble() * 256.0;
    offsetZ = random.nextDouble() * 256.0;
    for (var i = 0; i < 256; i++) {
      _perms[i] = i;
    }
    for (var i = 0; i < 256; i++) {
      final offset = random.nextInt(256 - i);
      final tmp = _perms[i];
      _perms[i] = _perms[offset + i];
      _perms[offset + i] = tmp;
    }
  }

  int _permute(int x) => _perms[x & 0xFF];

  double _corner(int index, double x, double y, double z, double base) {
    var t0 = base - x * x - y * y - z * z;
    if (t0 < 0.0) return 0.0;
    t0 *= t0;
    final g = _gradient[index];
    return t0 * t0 * (g[0] * x + g[1] * y + g[2] * z);
  }

  /// `SimplexNoise.get(x, y, z)`, rounded to a float like Java.
  double get(double xin0, double yin0, double zin0) {
    final xin = xin0 + offsetX;
    final yin = yin0 + offsetY;
    final zin = zin0 + offsetZ;
    final s = (xin + yin + zin) * 0.3333333333333333;
    final i = (xin + s).floor();
    final j = (yin + s).floor();
    final k = (zin + s).floor();
    final t = (i + j + k) * 0.16666666666666666;
    final x0 = xin - (i - t);
    final y0 = yin - (j - t);
    final z0 = zin - (k - t);
    int i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
      if (y0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
      } else if (x0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1;
      } else {
        i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1;
      }
    } else if (y0 < z0) {
      i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1;
    } else if (x0 < z0) {
      i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1;
    } else {
      i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
    }
    final x1 = x0 - i1 + 0.16666666666666666;
    final y1 = y0 - j1 + 0.16666666666666666;
    final z1 = z0 - k1 + 0.16666666666666666;
    final x2 = x0 - i2 + 0.3333333333333333;
    final y2 = y0 - j2 + 0.3333333333333333;
    final z2 = z0 - k2 + 0.3333333333333333;
    final x3 = x0 - 1.0 + 0.5;
    final y3 = y0 - 1.0 + 0.5;
    final z3 = z0 - 1.0 + 0.5;
    final ii = i & 0xFF;
    final jj = j & 0xFF;
    final kk = k & 0xFF;
    final gi0 = _permute(ii + _permute(jj + _permute(kk))) % 12;
    final gi1 = _permute(ii + i1 + _permute(jj + j1 + _permute(kk + k1))) % 12;
    final gi2 = _permute(ii + i2 + _permute(jj + j2 + _permute(kk + k2))) % 12;
    final gi3 = _permute(ii + 1 + _permute(jj + 1 + _permute(kk + 1))) % 12;
    final n0 = _corner(gi0, x0, y0, z0, 0.6);
    final n1 = _corner(gi1, x1, y1, z1, 0.6);
    final n2 = _corner(gi2, x2, y2, z2, 0.6);
    final n3 = _corner(gi3, x3, y3, z3, 0.6);
    return _float(32.0 * (n0 + n1 + n2 + n3));
  }
}

double mthSqrt(double v) => _float(math.sqrt(v));
