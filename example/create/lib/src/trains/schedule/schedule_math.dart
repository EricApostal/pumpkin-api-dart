// Java number semantics the schedule code relies on (pure).
import 'dart:typed_data';

final Float32List _f32 = Float32List(1);

/// Rounds to a Java `float`.
double toFloat32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// `(int) d`: truncation that saturates at the int range and maps NaN to 0.
int javaInt(double d) {
  if (d.isNaN) return 0;
  if (d >= 2147483647) return 2147483647;
  if (d <= -2147483648) return -2147483648;
  return d.toInt();
}

/// `Mth.clamp(int, min, max)`.
int clampInt(int value, int min, int max) => value < min ? min : (value > max ? max : value);

/// `Mth.clamp(double, min, max)`.
double clampDouble(double value, double min, double max) => value < min ? min : (value > max ? max : value);
