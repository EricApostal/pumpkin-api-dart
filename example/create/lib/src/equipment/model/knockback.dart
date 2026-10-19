// `LivingEntity.knockback(strength, x, z)` as a pure function. Pure.
import 'dart:math' as math;

import 'vec.dart';

/// The velocity after `knockback(strength, x, z)`: horizontal motion halves and the push away
/// (`-(x, z).normalize() * strength`) is subtracted; on the ground the vertical part rises to
/// `min(0.4, y / 2 + strength)`. Returns `null` when nothing is applied (resistance leaves no
/// strength).
V3? knockbackResult({
  required double strength,
  required double x,
  required double z,
  required V3 current,
  required bool onGround,
  double knockbackResistance = 0,
}) {
  final s = strength * (1.0 - knockbackResistance);
  if (!(s > 0)) return null;
  final len = math.sqrt(x * x + z * z);
  final dx = len < 1.0E-5 ? 0.0 : x / len * s;
  final dz = len < 1.0E-5 ? 0.0 : z / len * s;
  final y = onGround ? math.min(0.4, current.$2 / 2 + s) : current.$2;
  return (current.$1 / 2 - dx, y, current.$3 / 2 - dz);
}
