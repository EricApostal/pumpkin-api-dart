// A small port of catnip's `VecHelper` (the parts the equipment code uses). Pure.
import 'dart:math' as math;

import 'dir.dart';

typedef V3 = (double, double, double);

const V3 vzero = (0.0, 0.0, 0.0);

/// Vector maths on `(double, double, double)`. Method names carry a `v` prefix so they never
/// clash with `Vec3Math` of `pumpkin_api` in files that import both.
extension V3Math on (double, double, double) {
  V3 vplus(V3 o) => ($1 + o.$1, $2 + o.$2, $3 + o.$3);
  V3 vminus(V3 o) => ($1 - o.$1, $2 - o.$2, $3 - o.$3);
  V3 vscale(double k) => ($1 * k, $2 * k, $3 * k);
  double vdot(V3 o) => $1 * o.$1 + $2 * o.$2 + $3 * o.$3;
  V3 vcross(V3 o) => ($2 * o.$3 - $3 * o.$2, $3 * o.$1 - $1 * o.$3, $1 * o.$2 - $2 * o.$1);
  double get vlenSqr => $1 * $1 + $2 * $2 + $3 * $3;
  double get vlen => math.sqrt(vlenSqr);

  /// `Vec3.normalize()`: zero vectors stay zero.
  V3 get vnorm {
    final l = vlen;
    return l < 1.0E-5 ? vzero : ($1 / l, $2 / l, $3 / l);
  }

  double vdist(V3 o) => vminus(o).vlen;
}

/// `VecHelper.rotate(vec, deg, axis)` (Java uses the float sin/cos table; plain
/// `dart:math` differs by less than 1e-6).
V3 rotateVec(V3 vec, double deg, Ax axis) {
  if (deg == 0) return vec;
  if (vec == vzero) return vec;
  final angle = deg / 180 * math.pi;
  final s = math.sin(angle);
  final c = math.cos(angle);
  final (x, y, z) = vec;
  return switch (axis) {
    Ax.x => (x, y * c - z * s, z * c + y * s),
    Ax.y => (x * c + z * s, y, z * c - x * s),
    Ax.z => (x * c - y * s, y * c + x * s, z),
  };
}

/// `VecHelper.lookAt(vec, fwd)`.
V3 lookAtVec(V3 vec, V3 fwd) {
  fwd = fwd.vnorm;
  var up = (0.0, 1.0, 0.0);
  final dot = fwd.vdot(up);
  if (dot.abs() > 1 - 1.0E-3) up = (0.0, 0.0, dot > 0 ? 1.0 : -1.0);
  final right = fwd.vcross(up).vnorm;
  up = right.vcross(fwd).vnorm;
  final x = vec.$1 * right.$1 + vec.$2 * up.$1 + vec.$3 * fwd.$1;
  final y = vec.$1 * right.$2 + vec.$2 * up.$2 + vec.$3 * fwd.$2;
  final z = vec.$1 * right.$3 + vec.$2 * up.$3 + vec.$3 * fwd.$3;
  return (x, y, z);
}

/// `Entity.getLookAngle()` from yaw / pitch in degrees.
V3 lookVector(double yawDeg, double pitchDeg) {
  final p = pitchDeg * (math.pi / 180);
  final y = -yawDeg * (math.pi / 180);
  final cy = math.cos(y), sy = math.sin(y), cp = math.cos(p), sp = math.sin(p);
  return (sy * cp, -sp, cy * cp);
}

/// `Vec3.xRot(angle)` / `yRot(angle)` (radians), as used by `getGunBarrelVec`.
V3 xRot(V3 v, double rad) {
  final c = math.cos(rad), s = math.sin(rad);
  return (v.$1, v.$2 * c + v.$3 * s, v.$3 * c - v.$2 * s);
}

V3 yRot(V3 v, double rad) {
  final c = math.cos(rad), s = math.sin(rad);
  return (v.$1 * c + v.$3 * s, v.$2, v.$3 * c - v.$1 * s);
}

/// `ShootableGadgetItemMethods.getGunBarrelVec` from the player's eye position,
/// rotations (degrees) and which hand fires.
V3 gunBarrelVec({
  required V3 eyePos,
  required double yRotDeg,
  required double xRotDeg,
  required bool mainHand,
  required bool rightArmMain,
  required V3 rightHandForward,
}) {
  final yaw = yRotDeg / -180 * math.pi;
  final pitch = xRotDeg / -180 * math.pi;
  final flip = mainHand == rightArmMain ? -1.0 : 1.0;
  final noTransform = (flip * rightHandForward.$1, rightHandForward.$2, rightHandForward.$3);
  return eyePos.vplus(yRot(xRot(noTransform, pitch), yaw));
}
