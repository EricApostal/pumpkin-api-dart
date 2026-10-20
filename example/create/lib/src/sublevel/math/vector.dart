// The JOML types the Sable sub-level model uses, as mutable Dart classes.
//
// Sable's model mutates its vectors in place (`pose.position().set(...)`,
// `dest.expandTo(...)`), so these are deliberately *not* the immutable `Vec3`
// records of `common/vec_helper.dart`. `Vector3d`/`Vector3i`/`Quaterniond`/
// `Matrix4d` mirror `org.joml` one-to-one, including the `dest` overloads, so
// the Java code can be ported statement by statement. Converting to the record
// types the rest of the port uses goes through `JOMLConversion`.
//
// Pure: no host imports.
import 'dart:math' as math;
import 'dart:typed_data';

/// `org.joml.Vector3d`: a mutable 3-component double vector.
final class Vector3d {
  double x;
  double y;
  double z;

  Vector3d([this.x = 0.0, this.y = 0.0, this.z = 0.0]);

  /// `new Vector3d(Vector3dc)`.
  Vector3d.copy(Vector3d other)
    : x = other.x,
      y = other.y,
      z = other.z;

  Vector3d set(double x, double y, double z) {
    this.x = x;
    this.y = y;
    this.z = z;
    return this;
  }

  Vector3d setFrom(Vector3d other) => set(other.x, other.y, other.z);

  Vector3d setScalar(double value) => set(value, value, value);

  Vector3d zero() => set(0.0, 0.0, 0.0);

  Vector3d add(Vector3d other) {
    x += other.x;
    y += other.y;
    z += other.z;
    return this;
  }

  /// `add(Vector3dc, Vector3d dest)`.
  Vector3d addInto(Vector3d other, Vector3d dest) =>
      dest.set(x + other.x, y + other.y, z + other.z);

  Vector3d sub(Vector3d other) {
    x -= other.x;
    y -= other.y;
    z -= other.z;
    return this;
  }

  /// `sub(Vector3dc, Vector3d dest)`; this vector is unchanged.
  Vector3d subInto(Vector3d other, Vector3d dest) =>
      dest.set(x - other.x, y - other.y, z - other.z);

  Vector3d mul(double scalar) {
    x *= scalar;
    y *= scalar;
    z *= scalar;
    return this;
  }

  /// `mul(Vector3dc)`: component-wise.
  Vector3d mulVec(Vector3d other) {
    x *= other.x;
    y *= other.y;
    z *= other.z;
    return this;
  }

  /// `mul(Vector3dc, Vector3d dest)`: component-wise into [dest].
  Vector3d mulVecInto(Vector3d other, Vector3d dest) =>
      dest.set(x * other.x, y * other.y, z * other.z);

  /// `mul(double, Vector3d dest)`.
  Vector3d mulInto(double scalar, Vector3d dest) =>
      dest.set(x * scalar, y * scalar, z * scalar);

  Vector3d div(double scalar) {
    x /= scalar;
    y /= scalar;
    z /= scalar;
    return this;
  }

  /// `div(Vector3dc, Vector3d dest)`: component-wise division.
  Vector3d divVecInto(Vector3d other, Vector3d dest) =>
      dest.set(x / other.x, y / other.y, z / other.z);

  Vector3d negate() {
    x = -x;
    y = -y;
    z = -z;
    return this;
  }

  /// `fma(scalar, other)`: `this += other * scalar`.
  Vector3d fma(double scalar, Vector3d other) {
    x += other.x * scalar;
    y += other.y * scalar;
    z += other.z * scalar;
    return this;
  }

  Vector3d lerp(Vector3d other, double t) {
    x += (other.x - x) * t;
    y += (other.y - y) * t;
    z += (other.z - z) * t;
    return this;
  }

  double dot(Vector3d other) => x * other.x + y * other.y + z * other.z;

  Vector3d cross(Vector3d other) {
    final nx = y * other.z - z * other.y;
    final ny = z * other.x - x * other.z;
    final nz = x * other.y - y * other.x;
    return set(nx, ny, nz);
  }

  double get lengthSquared => x * x + y * y + z * z;

  double get length => math.sqrt(lengthSquared);

  double distanceSquared(Vector3d other) {
    final dx = x - other.x, dy = y - other.y, dz = z - other.z;
    return dx * dx + dy * dy + dz * dz;
  }

  double distance(Vector3d other) => math.sqrt(distanceSquared(other));

  Vector3d normalize() {
    final len = length;
    return len == 0.0 ? zero() : div(len);
  }

  Vector3d normalize(Vector3d dest) => dest.setFrom(this)..normalize();

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  @override
  bool operator ==(Object other) =>
      other is Vector3d && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}

/// `org.joml.Vector3i`: a mutable 3-component int vector.
final class Vector3i {
  int x;
  int y;
  int z;

  Vector3i([this.x = 0, this.y = 0, this.z = 0]);

  Vector3i.copy(Vector3i other)
    : x = other.x,
      y = other.y,
      z = other.z;

  Vector3i set(int x, int y, int z) {
    this.x = x;
    this.y = y;
    this.z = z;
    return this;
  }

  Vector3i setFrom(Vector3i other) => set(other.x, other.y, other.z);

  Vector3i add(Vector3i other) {
    x += other.x;
    y += other.y;
    z += other.z;
    return this;
  }

  Vector3i sub(Vector3i other) {
    x -= other.x;
    y -= other.y;
    z -= other.z;
    return this;
  }

  Vector3i min(Vector3i other) {
    x = math.min(x, other.x);
    y = math.min(y, other.y);
    z = math.min(z, other.z);
    return this;
  }

  Vector3i max(Vector3i other) {
    x = math.max(x, other.x);
    y = math.max(y, other.y);
    z = math.max(z, other.z);
    return this;
  }

  @override
  bool operator ==(Object other) =>
      other is Vector3i && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}

/// `org.joml.Quaterniond`: a mutable double quaternion (`x`, `y`, `z`, `w`).
final class Quaterniond {
  double x;
  double y;
  double z;
  double w;

  /// The identity quaternion.
  Quaterniond([this.x = 0.0, this.y = 0.0, this.z = 0.0, this.w = 1.0]);

  Quaterniond.copy(Quaterniond other)
    : x = other.x,
      y = other.y,
      z = other.z,
      w = other.w;

  Quaterniond set(double x, double y, double z, double w) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.w = w;
    return this;
  }

  Quaterniond setFrom(Quaterniond other) => set(other.x, other.y, other.z, other.w);

  Quaterniond identity() => set(0.0, 0.0, 0.0, 1.0);

  double get lengthSquared => x * x + y * y + z * z + w * w;

  double get length => math.sqrt(lengthSquared);

  Quaterniond normalize() {
    final len = length;
    if (len == 0.0) return identity();
    x /= len;
    y /= len;
    z /= len;
    w /= len;
    return this;
  }

  Quaterniond conjugate() {
    x = -x;
    y = -y;
    z = -z;
    return this;
  }

  /// `this * other`.
  Quaterniond mul(Quaterniond other) {
    final nx = w * other.x + x * other.w + y * other.z - z * other.y;
    final ny = w * other.y - x * other.z + y * other.w + z * other.x;
    final nz = w * other.z + x * other.y - y * other.x + z * other.w;
    final nw = w * other.w - x * other.x - y * other.y - z * other.z;
    return set(nx, ny, nz, nw);
  }

  /// `mul(double)`.
  Quaterniond mulScalar(double scalar) {
    x *= scalar;
    y *= scalar;
    z *= scalar;
    w *= scalar;
    return this;
  }

  /// `this * conjugate(other)`, i.e. the rotation taking [other] to `this`.
  Quaterniond difference(Quaterniond other, Quaterniond dest) =>
      dest.setFrom(this).mul(Quaterniond.copy(other).conjugate());

  /// `this / other` (the inverse of a unit quaternion is its conjugate).
  Quaterniond div(Quaterniond other, Quaterniond dest) =>
      dest.setFrom(this).mul(Quaterniond.copy(other).conjugate());

  /// `Quaterniond.angle()`: the rotation angle in radians, in `[0, pi]`.
  double angle() => 2.0 * math.acos(math.min(w.abs(), 1.0));

  /// `Quaterniond.transform(Vector3dc, Vector3d)`.
  Vector3d transform(Vector3d v, Vector3d dest) {
    // t = 2 * cross(q.xyz, v); v' = v + w * t + cross(q.xyz, t)
    final tx = 2.0 * (y * v.z - z * v.y);
    final ty = 2.0 * (z * v.x - x * v.z);
    final tz = 2.0 * (x * v.y - y * v.x);
    return dest.set(
      v.x + w * tx + (y * tz - z * ty),
      v.y + w * ty + (z * tx - x * tz),
      v.z + w * tz + (x * ty - y * tx),
    );
  }

  /// `Quaterniond.transformInverse(Vector3dc, Vector3d)`.
  Vector3d transformInverse(Vector3d v, Vector3d dest) {
    final inverse = Quaterniond(-x, -y, -z, w);
    return inverse.transform(v, dest);
  }

  /// `Quaterniond.nlerp(Quaterniondc, double, Quaterniond dest)`.
  Quaterniond nlerp(Quaterniond other, double t, Quaterniond dest) {
    var ox = other.x, oy = other.y, oz = other.z, ow = other.w;
    final dot = x * ox + y * oy + z * oz + w * ow;
    if (dot < 0.0) {
      ox = -ox;
      oy = -oy;
      oz = -oz;
      ow = -ow;
    }
    dest.set(
      x + (ox - x) * t,
      y + (oy - y) * t,
      z + (oz - z) * t,
      w + (ow - w) * t,
    );
    return dest.normalize();
  }

  @override
  bool operator ==(Object other) =>
      other is Quaterniond && other.x == x && other.y == y && other.z == z && other.w == w;

  @override
  int get hashCode => Object.hash(x, y, z, w);

  @override
  String toString() => '($x, $y, $z, $w)';
}

/// `org.joml.Matrix4d`: a mutable 4x4 matrix, row-major.
///
/// Row-major is a Dart-side choice (JOML stores column-major); every method
/// here is written consistently so callers never index [m] directly. Only the
/// affine subset Sable uses is implemented: translation, rotation, scale,
/// affine inverse and point transformation.
final class Matrix4d {
  /// The 16 values, row-major.
  final Float64List m = Float64List(16);

  Matrix4d() {
    identity();
  }

  Matrix4d.copy(Matrix4d other) {
    m.setAll(0, other.m);
  }

  Matrix4d identity() {
    m.fillRange(0, 16, 0.0);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return this;
  }

  Matrix4d setFrom(Matrix4d other) {
    m.setAll(0, other.m);
    return this;
  }

  /// `translate(double, double, double)`: post-multiplies a translation.
  Matrix4d translate(double x, double y, double z) {
    final t = Matrix4d()..m.setAll(0, [1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1]);
    return _postMultiply(t);
  }

  /// `scale(Vector3dc)`: post-multiplies a scale.
  Matrix4d scale(Vector3d s) => scaleXYZ(s.x, s.y, s.z);

  Matrix4d scaleXYZ(double x, double y, double z) {
    final s = Matrix4d()..m.setAll(0, [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]);
    return _postMultiply(s);
  }

  /// `rotate(Quaterniondc)`: post-multiplies the rotation matrix of [q].
  Matrix4d rotate(Quaterniond q) {
    final xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
    final xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
    final wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;
    final r = Matrix4d()
      ..m.setAll(0, [
        1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0, //
        2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0, //
        2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0, //
        0, 0, 0, 1,
      ]);
    return _postMultiply(r);
  }

  Matrix4d _postMultiply(Matrix4d o) {
    final a = Float64List.fromList(m);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 4 + k] * o.m[k * 4 + col];
        }
        m[row * 4 + col] = sum;
      }
    }
    return this;
  }

  /// `transformPosition(Vector3dc, Vector3d)` (w = 1, no perspective divide).
  Vector3d transformPosition(Vector3d v, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final x = m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3];
    final y = m[4] * v.x + m[5] * v.y + m[6] * v.z + m[7];
    final z = m[8] * v.x + m[9] * v.y + m[10] * v.z + m[11];
    return out.set(x, y, z);
  }

  /// `invertAffine()`: inverts the affine transform in place.
  ///
  /// Returns `this`; a singular matrix is left untouched (JOML also returns
  /// the receiver).
  Matrix4d invertAffine() {
    final a00 = m[0], a01 = m[1], a02 = m[2];
    final a10 = m[4], a11 = m[5], a12 = m[6];
    final a20 = m[8], a21 = m[9], a22 = m[10];

    final b01 = a22 * a11 - a12 * a21;
    final b11 = -a22 * a10 + a12 * a20;
    final b21 = a21 * a10 - a11 * a20;

    var det = a00 * b01 + a01 * b11 + a02 * b21;
    if (det == 0.0) return this;
    det = 1.0 / det;

    final i00 = b01 * det;
    final i01 = (-a22 * a01 + a02 * a21) * det;
    final i02 = (a12 * a01 - a02 * a11) * det;
    final i10 = b11 * det;
    final i11 = (a22 * a00 - a02 * a20) * det;
    final i12 = (-a12 * a00 + a02 * a10) * det;
    final i20 = b21 * det;
    final i21 = (-a21 * a00 + a01 * a20) * det;
    final i22 = (a11 * a00 - a01 * a10) * det;

    final tx = m[3], ty = m[7], tz = m[11];
    m[0] = i00;
    m[1] = i01;
    m[2] = i02;
    m[3] = -(i00 * tx + i01 * ty + i02 * tz);
    m[4] = i10;
    m[5] = i11;
    m[6] = i12;
    m[7] = -(i10 * tx + i11 * ty + i12 * tz);
    m[8] = i20;
    m[9] = i21;
    m[10] = i22;
    m[11] = -(i20 * tx + i21 * ty + i22 * tz);
    m[12] = 0.0;
    m[13] = 0.0;
    m[14] = 0.0;
    m[15] = 1.0;
    return this;
  }

  @override
  String toString() => 'Matrix4d(${[for (var r = 0; r < 4; r++) m.sublist(r * 4, r * 4 + 4)].join(', ')})';
}
