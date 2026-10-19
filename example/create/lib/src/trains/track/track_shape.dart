// `TrackShape` (pure): the 19 shapes of a track block state, with the axes they carry.
import 'dart:math' as math;

import '../../common/common.dart';

/// `Vec3.normalize()`: zero for vectors shorter than 1e-5.
Vec3 vnorm(Vec3 v) {
  final len = math.sqrt(v.$1 * v.$1 + v.$2 * v.$2 + v.$3 * v.$3);
  return len < 1.0E-5 ? vec3Zero : (v.$1 / len, v.$2 / len, v.$3 / len);
}

/// `Vec3.multiply(x, y, z)` (component-wise product).
Vec3 vmul(Vec3 v, double x, double y, double z) => (v.$1 * x, v.$2 * y, v.$3 * z);

/// `Vec3.distanceToSqr`.
double vdistSqr(Vec3 a, Vec3 b) => (a - b).lengthSquared;

/// `Vec3.scale`.
Vec3 vscale(Vec3 v, double k) => (v.$1 * k, v.$2 * k, v.$3 * k);

/// `Vec3.atBottomCenterOf(pos)`.
Vec3 atBottomCenterOf(Pos p) => p.bottomCenter;

/// `TrackShape`.
enum TrackShape {
  none('', (0.0, 0.0, 0.0), null, 0, (0.0, 1.0, 0.0)),
  zo('z_ortho', (0.0, 0.0, 1.0), null, 0, (0.0, 1.0, 0.0)),
  xo('x_ortho', (1.0, 0.0, 0.0), null, 0, (0.0, 1.0, 0.0)),
  pd('diag', (1.0, 0.0, 1.0), null, 0, (0.0, 1.0, 0.0)),
  nd('diag_2', (-1.0, 0.0, 1.0), null, 0, (0.0, 1.0, 0.0)),
  an('ascending', (0.0, 1.0, -1.0), null, 180, (0.0, 1.0, 1.0)),
  as_('ascending', (0.0, 1.0, 1.0), null, 0, (0.0, 1.0, -1.0)),
  ae('ascending', (1.0, 1.0, 0.0), null, 270, (-1.0, 1.0, 0.0)),
  aw('ascending', (-1.0, 1.0, 0.0), null, 90, (1.0, 1.0, 0.0)),

  tn('teleport', (0.0, 0.0, -1.0), null, 180, (0.0, 1.0, 0.0)),
  ts('teleport', (0.0, 0.0, 1.0), null, 0, (0.0, 1.0, 0.0)),
  te('teleport', (1.0, 0.0, 0.0), null, 270, (0.0, 1.0, 0.0)),
  tw('teleport', (-1.0, 0.0, 0.0), null, 90, (0.0, 1.0, 0.0)),

  crO('cross_ortho', (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), 0, (0.0, 1.0, 0.0)),
  crD('cross_diag', (1.0, 0.0, 1.0), (-1.0, 0.0, 1.0), 0, (0.0, 1.0, 0.0)),
  crPdx('cross_d1_xo', (1.0, 0.0, 0.0), (1.0, 0.0, 1.0), 0, (0.0, 1.0, 0.0)),
  crPdz('cross_d1_zo', (0.0, 0.0, 1.0), (1.0, 0.0, 1.0), 0, (0.0, 1.0, 0.0)),
  crNdx('cross_d2_xo', (1.0, 0.0, 0.0), (-1.0, 0.0, 1.0), 0, (0.0, 1.0, 0.0)),
  crNdz('cross_d2_zo', (0.0, 0.0, 1.0), (-1.0, 0.0, 1.0), 0, (0.0, 1.0, 0.0));

  const TrackShape(this._model, this._axis, this._secondAxis, this._modelRotation, this._rawNormal);

  final String _model;
  final Vec3 _axis;
  final Vec3? _secondAxis;
  final int _modelRotation;
  final Vec3 _rawNormal;

  /// `getSerializedName()` (`Lang.asId(name())`), the value of the `shape` block state property.
  String get serializedName => switch (this) {
    TrackShape.as_ => 'as',
    TrackShape.crO => 'cr_o',
    TrackShape.crD => 'cr_d',
    TrackShape.crPdx => 'cr_pdx',
    TrackShape.crPdz => 'cr_pdz',
    TrackShape.crNdx => 'cr_ndx',
    TrackShape.crNdz => 'cr_ndz',
    _ => name,
  };

  /// The shape with the given `shape` property value, or `null`.
  static TrackShape? byName(String serialized) {
    for (final s in TrackShape.values) {
      if (s.serializedName == serialized) return s;
    }
    return null;
  }

  String getModel() => _model;

  /// `getAxes()`.
  List<Vec3> getAxes() => _secondAxis == null ? [_axis] : [_axis, _secondAxis];

  bool isJunction() => _secondAxis != null;

  bool isPortal() => this == te || this == tn || this == ts || this == tw;

  /// `asPortal(horizontalFacing)`.
  static TrackShape asPortal(Direction horizontalFacing) {
    switch (horizontalFacing) {
      case Direction.east:
        return te;
      case Direction.north:
        return tn;
      case Direction.south:
        return ts;
      default:
        return tw;
    }
  }

  /// `getNormal()`: the normalized up vector of the shape.
  Vec3 getNormal() => vnorm(_rawNormal);

  int getModelRotation() => _modelRotation;

  static final Map<TrackShape, TrackShape> _zMirror = {
    pd: nd,
    nd: pd,
    an: as_,
    as_: an,
    crPdx: crNdx,
    crNdx: crPdx,
    crPdz: crNdz,
    crNdz: crPdz,
  };

  static final Map<TrackShape, TrackShape> _xMirror = {
    pd: nd,
    nd: pd,
    ae: aw,
    aw: ae,
    crPdx: crNdx,
    crNdx: crPdx,
    crPdz: crNdz,
    crNdz: crPdz,
  };

  static final Map<TrackShape, TrackShape> _clockwise = {
    pd: nd,
    nd: pd,
    xo: zo,
    zo: xo,
    ae: as_,
    as_: aw,
    aw: an,
    an: ae,
    crPdx: crNdz,
    crNdx: crPdz,
    crPdz: crNdx,
    crNdz: crPdx,
  };

  /// `mirror(Mirror)`.
  TrackShape mirror(BlockMirror mirror) => mirror == BlockMirror.none
      ? this
      : mirror == BlockMirror.frontBack
      ? (_xMirror[this] ?? this)
      : (_zMirror[this] ?? this);

  /// `rotate(Rotation)`.
  TrackShape rotate(BlockRotation rotation) {
    var shape = this;
    for (var i = 0; i < rotation.index; i++) {
      shape = _clockwise[shape] ?? shape;
    }
    return shape;
  }
}
