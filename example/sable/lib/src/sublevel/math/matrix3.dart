// A 3x3 matrix, the part of JOML's `Matrix3d` the physics code uses.
//
// Sable's floating-block controller and the mass tracker work in principal
// inertia space: outer products, inertia tensors, their inverses and
// transforms. The port's `Vector3d`/`Quaterniond` live in `vector.dart`; this
// is the matching 3x3.
//
// Storage is row major (`m00 m01 m02 / m10 m11 m12 / m20 m21 m22`), like JOML.
//
// Pure: no host imports.
import 'dart:math' as math;

import 'vector.dart';

/// A mutable 3x3 matrix of doubles.
final class Matrix3d {
  double m00;
  double m01;
  double m02;
  double m10;
  double m11;
  double m12;
  double m20;
  double m21;
  double m22;

  Matrix3d([
    this.m00 = 1.0,
    this.m01 = 0.0,
    this.m02 = 0.0,
    this.m10 = 0.0,
    this.m11 = 1.0,
    this.m12 = 0.0,
    this.m20 = 0.0,
    this.m21 = 0.0,
    this.m22 = 1.0,
  ]);

  /// A copy of [other].
  Matrix3d.copy(Matrix3d other)
    : m00 = other.m00,
      m01 = other.m01,
      m02 = other.m02,
      m10 = other.m10,
      m11 = other.m11,
      m12 = other.m12,
      m20 = other.m20,
      m21 = other.m21,
      m22 = other.m22;

  /// `new Matrix3d().zero()`.
  static Matrix3d zero() => Matrix3d(0, 0, 0, 0, 0, 0, 0, 0, 0);

  /// `new Matrix3d().identity()`.
  static Matrix3d identity() => Matrix3d();

  /// `set(m00, ..., m22)`.
  Matrix3d set(
    double m00,
    double m01,
    double m02,
    double m10,
    double m11,
    double m12,
    double m20,
    double m21,
    double m22,
  ) {
    this.m00 = m00;
    this.m01 = m01;
    this.m02 = m02;
    this.m10 = m10;
    this.m11 = m11;
    this.m12 = m12;
    this.m20 = m20;
    this.m21 = m21;
    this.m22 = m22;
    return this;
  }

  /// `set(other)`.
  Matrix3d setFrom(Matrix3d other) => set(
    other.m00,
    other.m01,
    other.m02,
    other.m10,
    other.m11,
    other.m12,
    other.m20,
    other.m21,
    other.m22,
  );

  /// `identity()`.
  Matrix3d makeIdentity() => set(1, 0, 0, 0, 1, 0, 0, 0, 1);

  /// `zero()`.
  Matrix3d makeZero() => set(0, 0, 0, 0, 0, 0, 0, 0, 0);

  /// `scale(scalar)`.
  Matrix3d scale(double scalar) => set(
    m00 * scalar,
    m01 * scalar,
    m02 * scalar,
    m10 * scalar,
    m11 * scalar,
    m12 * scalar,
    m20 * scalar,
    m21 * scalar,
    m22 * scalar,
  );

  /// `scale(scalar, dest)`.
  Matrix3d scaleInto(double scalar, Matrix3d dest) => dest
    ..m00 = m00 * scalar
    ..m01 = m01 * scalar
    ..m02 = m02 * scalar
    ..m10 = m10 * scalar
    ..m11 = m11 * scalar
    ..m12 = m12 * scalar
    ..m20 = m20 * scalar
    ..m21 = m21 * scalar
    ..m22 = m22 * scalar;

  /// `add(other)`.
  Matrix3d add(Matrix3d other) => set(
    m00 + other.m00,
    m01 + other.m01,
    m02 + other.m02,
    m10 + other.m10,
    m11 + other.m11,
    m12 + other.m12,
    m20 + other.m20,
    m21 + other.m21,
    m22 + other.m22,
  );

  /// `sub(other)`.
  Matrix3d sub(Matrix3d other) => set(
    m00 - other.m00,
    m01 - other.m01,
    m02 - other.m02,
    m10 - other.m10,
    m11 - other.m11,
    m12 - other.m12,
    m20 - other.m20,
    m21 - other.m21,
    m22 - other.m22,
  );

  /// `add(other, dest)`.
  Matrix3d addInto(Matrix3d other, Matrix3d dest) => dest
    ..m00 = m00 + other.m00
    ..m01 = m01 + other.m01
    ..m02 = m02 + other.m02
    ..m10 = m10 + other.m10
    ..m11 = m11 + other.m11
    ..m12 = m12 + other.m12
    ..m20 = m20 + other.m20
    ..m21 = m21 + other.m21
    ..m22 = m22 + other.m22;

  /// `sub(other, dest)`.
  Matrix3d subInto(Matrix3d other, Matrix3d dest) => dest
    ..m00 = m00 - other.m00
    ..m01 = m01 - other.m01
    ..m02 = m02 - other.m02
    ..m10 = m10 - other.m10
    ..m11 = m11 - other.m11
    ..m12 = m12 - other.m12
    ..m20 = m20 - other.m20
    ..m21 = m21 - other.m21
    ..m22 = m22 - other.m22;

  /// `mul(right)`.
  Matrix3d mul(Matrix3d right) => mulInto(right, this);

  /// `mul(right, dest)`.
  Matrix3d mulInto(Matrix3d right, Matrix3d dest) {
    final nm00 = m00 * right.m00 + m01 * right.m10 + m02 * right.m20;
    final nm01 = m00 * right.m01 + m01 * right.m11 + m02 * right.m21;
    final nm02 = m00 * right.m02 + m01 * right.m12 + m02 * right.m22;
    final nm10 = m10 * right.m00 + m11 * right.m10 + m12 * right.m20;
    final nm11 = m10 * right.m01 + m11 * right.m11 + m12 * right.m21;
    final nm12 = m10 * right.m02 + m11 * right.m12 + m12 * right.m22;
    final nm20 = m20 * right.m00 + m21 * right.m10 + m22 * right.m20;
    final nm21 = m20 * right.m01 + m21 * right.m11 + m22 * right.m21;
    final nm22 = m20 * right.m02 + m21 * right.m12 + m22 * right.m22;
    return dest.set(nm00, nm01, nm02, nm10, nm11, nm12, nm20, nm21, nm22);
  }

  /// `transpose()`.
  Matrix3d transpose() => set(m00, m10, m20, m01, m11, m21, m02, m12, m22);

  /// `transpose(dest)`.
  Matrix3d transposeInto(Matrix3d dest) => dest.set(m00, m10, m20, m01, m11, m21, m02, m12, m22);

  /// `determinant()`.
  double determinant() =>
      m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20);

  /// `trace()`.
  double trace() => m00 + m11 + m22;

  /// `invert()`; a singular matrix becomes all zeros, like JOML's
  /// `invert(invert)` returning false.
  Matrix3d invert() {
    final det = determinant();
    if (det == 0.0 || det.isNaN) return makeZero();

    final invDet = 1.0 / det;
    return set(
      (m11 * m22 - m12 * m21) * invDet,
      (m02 * m21 - m01 * m22) * invDet,
      (m01 * m12 - m02 * m11) * invDet,
      (m12 * m20 - m10 * m22) * invDet,
      (m00 * m22 - m02 * m20) * invDet,
      (m02 * m10 - m00 * m12) * invDet,
      (m10 * m21 - m11 * m20) * invDet,
      (m01 * m20 - m00 * m21) * invDet,
      (m00 * m11 - m01 * m10) * invDet,
    );
  }

  /// `invert(dest)`.
  Matrix3d invertInto(Matrix3d dest) => dest.setFrom(Matrix3d.copy(this)..invert());

  /// `transform(v, dest)`: matrix times column vector.
  Vector3d transform(Vector3d v, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final x = m00 * v.x + m01 * v.y + m02 * v.z;
    final y = m10 * v.x + m11 * v.y + m12 * v.z;
    final z = m20 * v.x + m21 * v.y + m22 * v.z;
    return out.set(x, y, z);
  }

  /// `mulLocal(right)`: [this] = [this] * [right].
  Matrix3d mulLocal(Matrix3d right) => mulInto(right, this);

  /// `set(quaternion)`: the rotation matrix of [q].
  Matrix3d setFromQuaternion(Quaterniond q) {
    final x = q.x, y = q.y, z = q.z, w = q.w;
    final x2 = x + x, y2 = y + y, z2 = z + z;
    final xx = x * x2, xy = x * y2, xz = x * z2;
    final yy = y * y2, yz = y * z2, zz = z * z2;
    final wx = w * x2, wy = w * y2, wz = w * z2;
    return set(
      1 - (yy + zz), xy - wz, xz + wy, //
      xy + wz, 1 - (xx + zz), yz - wx, //
      xz - wy, yz + wx, 1 - (xx + yy),
    );
  }

  /// `setOuterProduct(a, b, scale, dest)`: `scale * a * bᵀ`.
  static Matrix3d setOuterProduct(Vector3d a, Vector3d b, double scale, Matrix3d dest) => dest.set(
    a.x * b.x * scale,
    a.x * b.y * scale,
    a.x * b.z * scale,
    a.y * b.x * scale,
    a.y * b.y * scale,
    a.y * b.z * scale,
    a.z * b.x * scale,
    a.z * b.y * scale,
    a.z * b.z * scale,
  );

  /// `fmaOuterProduct(a, b, scale, dest)`: `dest += scale * a * bᵀ`.
  static Matrix3d fmaOuterProduct(Vector3d a, Vector3d b, double scale, Matrix3d dest) => dest
    ..m00 += a.x * b.x * scale
    ..m01 += a.x * b.y * scale
    ..m02 += a.x * b.z * scale
    ..m10 += a.y * b.x * scale
    ..m11 += a.y * b.y * scale
    ..m12 += a.y * b.z * scale
    ..m20 += a.z * b.x * scale
    ..m21 += a.z * b.y * scale
    ..m22 += a.z * b.z * scale;

  /// `fmaInertiaTensor(angularVelocity, scale, dest)`:
  /// `dest += scale * (|w|²·I − w·wᵀ)`, the inertia of a rotating frame.
  static Matrix3d fmaInertiaTensor(Vector3d angularVelocity, double scale, Matrix3d dest) {
    final w2 = angularVelocity.lengthSquared;
    final x = angularVelocity.x, y = angularVelocity.y, z = angularVelocity.z;
    dest.m00 += scale * (w2 - x * x);
    dest.m01 += scale * (-x * y);
    dest.m02 += scale * (-x * z);
    dest.m10 += scale * (-y * x);
    dest.m11 += scale * (w2 - y * y);
    dest.m12 += scale * (-y * z);
    dest.m20 += scale * (-z * x);
    dest.m21 += scale * (-z * y);
    dest.m22 += scale * (w2 - z * z);
    return dest;
  }

  /// `vᵀ M v`.
  static double multiplyInnerProduct(Vector3d v, Matrix3d m, Vector3d w) =>
      v.x * (m.m00 * w.x + m.m01 * w.y + m.m02 * w.z) +
      v.y * (m.m10 * w.x + m.m11 * w.y + m.m12 * w.z) +
      v.z * (m.m20 * w.x + m.m21 * w.y + m.m22 * w.z);

  /// `Math.sqrt(det)`, `0` for a degenerate matrix.
  double sqrtDeterminant() => math.sqrt(math.max(determinant(), 0.0));

  @override
  bool operator ==(Object other) =>
      other is Matrix3d &&
      other.m00 == m00 &&
      other.m01 == m01 &&
      other.m02 == m02 &&
      other.m10 == m10 &&
      other.m11 == m11 &&
      other.m12 == m12 &&
      other.m20 == m20 &&
      other.m21 == m21 &&
      other.m22 == m22;

  @override
  int get hashCode => Object.hash(m00, m01, m02, m10, m11, m12, m20, m21, m22);

  @override
  String toString() => 'Matrix3d([$m00, $m01, $m02], [$m10, $m11, $m12], [$m20, $m21, $m22])';
}
