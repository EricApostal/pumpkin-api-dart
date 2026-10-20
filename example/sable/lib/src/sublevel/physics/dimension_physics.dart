// `dev.ryanhcode.sable.physics.config.dimension_physics`: per-dimension gravity,
// air pressure, magnetic north and drag.
//
// `DimensionPhysics.STREAM_CODEC` is hand written (not an NBT codec), so the
// `dimension_physics` payload is a plain byte stream:
//
// ```
// Identifier dimension          (UTF-8 string)
// int        priority
// optional float   universal_drag
// optional Vector3f base_gravity
// optional double  base_pressure
// optional BezierResourceFunction pressure_function   (VarInt count, 3 doubles each)
// optional Vector3f magnetic_north
// bool       ignore_chunks
// ```
//
// `optional` is a boolean followed by the value (`ByteBufCodecs.optional`).
//
// Pure: no host imports.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../host/sub_level_host.dart';
import '../math/vector.dart';
import '../network/wire.dart';

/// `BezierResourceFunction.BezierPoint`: one control point of the air-pressure
/// curve.
final class BezierPoint {
  /// The altitude the point sits at.
  final double altitude;

  /// The air pressure at [altitude].
  final double value;

  /// The slope of the curve at [altitude].
  final double slope;

  const BezierPoint(this.altitude, this.value, this.slope);

  /// `BezierPoint.STREAM_CODEC`.
  static void write(PacketWriter buf, BezierPoint point) {
    buf.writeDouble(point.altitude);
    buf.writeDouble(point.value);
    buf.writeDouble(point.slope);
  }

  /// `BezierPoint.STREAM_CODEC`.
  static BezierPoint read(PacketReader buf) =>
      BezierPoint(buf.readDouble(), buf.readDouble(), buf.readDouble());

  @override
  bool operator ==(Object other) =>
      other is BezierPoint &&
      other.altitude == altitude &&
      other.value == value &&
      other.slope == slope;

  @override
  int get hashCode => Object.hash(altitude, value, slope);

  @override
  String toString() => 'BezierPoint($altitude, $value, $slope)';
}

/// `BezierResourceFunction`: the piecewise cubic curve that maps altitude to air
/// pressure.
final class BezierResourceFunction {
  /// The control points, in ascending altitude.
  final List<BezierPoint> points;

  BezierResourceFunction([List<BezierPoint>? points]) : points = points ?? [];

  /// `pointSize()`.
  int get pointSize => points.length;

  /// `addPoint(point)`.
  void addPoint(BezierPoint point) => points.add(point);

  /// `evaluateFunction(position)`: the cubic through the two neighbouring
  /// points, clamped to at least zero.
  double evaluateFunction(double position) {
    if (points.isEmpty) return 1;
    if (points.length == 1) return points[0].value;

    var index = -1;
    for (final point in points) {
      if (position < point.altitude) break;
      index++;
    }
    if (index == -1) return points[0].value;
    if (index >= points.length - 1) return points[points.length - 1].value;

    final point1 = points[index];
    final point2 = points[index + 1];

    final relativeX = point2.altitude - point1.altitude;
    final relativeY = point2.value - point1.value;
    final slope1 = point1.slope;
    final slope2 = point2.slope;
    final t = (position - point1.altitude) / relativeX;

    final cubicFactor = (slope1 + slope2) * relativeX - 2 * relativeY;
    final quadraticFactor = 3 * relativeY - (2 * slope1 + slope2) * relativeX;
    final linearFactor = relativeX * slope1;

    return math.max(((cubicFactor * t + quadraticFactor) * t + linearFactor) * t + point1.value, 0);
  }

  /// `BezierResourceFunction.STREAM_CODEC`.
  void write(PacketWriter buf) {
    buf.writeVarInt(points.length);
    for (final point in points) {
      BezierPoint.write(buf, point);
    }
  }

  /// `BezierResourceFunction.STREAM_CODEC`.
  static BezierResourceFunction read(PacketReader buf) {
    final count = buf.readVarInt();
    if (count < 0) throw PacketException('Negative bezier point count $count');
    final points = <BezierPoint>[];
    for (var i = 0; i < count; i++) {
      points.add(BezierPoint.read(buf));
    }
    return BezierResourceFunction(points);
  }
}

/// `DimensionPhysics`: the physics settings of one dimension.
final class DimensionPhysics {
  /// `DEFAULT_GRAVITY`.
  static const (double, double, double) defaultGravity = (0.0, -11.0, 0.0);

  /// `DEFAULT_MAGNETIC_NORTH`.
  static const (double, double, double) defaultMagneticNorth = (0.0, 0.0, 0.0);

  /// `DEFAULT_PRESSURE`.
  static const double defaultPressure = 1.0;

  /// `DEFAULT_UNIVERSAL_DRAG`.
  static const double defaultUniversalDrag = 0.09;

  final String dimension;
  final int priority;
  final double? universalDrag;
  final (double, double, double)? baseGravity;
  final double? basePressure;
  final BezierResourceFunction? pressureFunction;
  final (double, double, double)? magneticNorth;
  final bool ignoreChunks;

  const DimensionPhysics({
    required this.dimension,
    this.priority = 1000,
    this.universalDrag,
    this.baseGravity,
    this.basePressure,
    this.pressureFunction,
    this.magneticNorth,
    this.ignoreChunks = false,
  });

  /// `DimensionPhysics.STREAM_CODEC` encoding.
  void write(PacketWriter buf) {
    buf.writeString(dimension);
    buf.writeInt(priority);
    buf.writeOptional(universalDrag, (w, v) => w.writeFloat(v));
    buf.writeOptional(baseGravity, (w, v) => SableBufferUtils.writeVector3f(w, Vector3d(v.$1, v.$2, v.$3)));
    buf.writeOptional(basePressure, (w, v) => w.writeDouble(v));
    buf.writeOptional(pressureFunction, (w, v) => v.write(w));
    buf.writeOptional(magneticNorth, (w, v) => SableBufferUtils.writeVector3f(w, Vector3d(v.$1, v.$2, v.$3)));
    buf.writeBool(ignoreChunks);
  }

  /// `DimensionPhysics.STREAM_CODEC` decoding.
  static DimensionPhysics read(PacketReader buf) {
    final dimension = buf.readString();
    final priority = buf.readInt();
    final universalDrag = buf.readOptional((r) => r.readFloat());
    final gravity = buf.readOptional((r) {
      final v = SableBufferUtils.readVector3f(r);
      return (v.x, v.y, v.z);
    });
    final basePressure = buf.readOptional((r) => r.readDouble());
    final pressureFunction = buf.readOptional(BezierResourceFunction.read);
    final north = buf.readOptional((r) {
      final v = SableBufferUtils.readVector3f(r);
      return (v.x, v.y, v.z);
    });
    final ignoreChunks = buf.readBool();

    return DimensionPhysics(
      dimension: dimension,
      priority: priority,
      universalDrag: universalDrag,
      baseGravity: gravity,
      basePressure: basePressure,
      pressureFunction: pressureFunction,
      magneticNorth: north,
      ignoreChunks: ignoreChunks,
    );
  }

  /// `DimensionPhysics.createDefault(level)`: an exponential pressure decay
  /// centred on sea level, clamped to 1.5 underground, with a 40 m drop-off at
  /// the build limit.
  static DimensionPhysics createDefault(SableLevel level, {int seaLevel = 64}) {
    final minAltitude = level.minY.toDouble();
    final maxAltitude = level.maxY.toDouble();

    const baseSlope = -0.004;
    const maxPressure = 1.5;
    const maxStep = 200.0;
    final smoothingAltitude = maxAltitude - 40;

    // Clamp the bottom-most point to a pressure of at most 1.5.
    var currentAltitude = math.max(minAltitude, math.log(maxPressure) / baseSlope + seaLevel);

    final pressureFunction = BezierResourceFunction();

    while (true) {
      final currentPressure = math.exp(baseSlope * (currentAltitude - seaLevel));
      final currentSlope = currentPressure * baseSlope;
      pressureFunction.addPoint(BezierPoint(currentAltitude, currentPressure, currentSlope));

      if (currentAltitude < seaLevel && currentAltitude + maxStep >= seaLevel) {
        currentAltitude = seaLevel.toDouble();
      } else if (currentAltitude < smoothingAltitude && currentAltitude + maxStep >= smoothingAltitude) {
        currentAltitude = smoothingAltitude;
      } else if (currentAltitude >= smoothingAltitude) {
        break;
      } else {
        currentAltitude += maxStep;
      }
    }

    final smoothingPressure = pressureFunction.points[pressureFunction.pointSize - 1].value;
    final finalSlope = -2 * smoothingPressure / (maxAltitude - smoothingAltitude);
    pressureFunction.addPoint(BezierPoint(maxAltitude, 0, finalSlope));

    return DimensionPhysics(
      dimension: level.dimensionId,
      priority: 0,
      universalDrag: defaultUniversalDrag,
      baseGravity: defaultGravity,
      basePressure: defaultPressure,
      pressureFunction: pressureFunction,
      magneticNorth: defaultMagneticNorth,
      ignoreChunks: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DimensionPhysics &&
      other.dimension == dimension &&
      other.priority == priority &&
      other.universalDrag == universalDrag &&
      other.baseGravity == baseGravity &&
      other.basePressure == basePressure &&
      other.magneticNorth == magneticNorth &&
      other.ignoreChunks == ignoreChunks &&
      _samePoints(other.pressureFunction, pressureFunction);

  @override
  int get hashCode => Object.hash(
    dimension,
    priority,
    universalDrag,
    baseGravity,
    basePressure,
    magneticNorth,
    ignoreChunks,
    pressureFunction?.points.length,
  );

  static bool _samePoints(BezierResourceFunction? a, BezierResourceFunction? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.points.length != b.points.length) return false;
    for (var i = 0; i < a.points.length; i++) {
      if (a.points[i] != b.points[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'DimensionPhysics[$dimension, priority=$priority]';
}

/// `DimensionPhysicsData`: the per-dimension table.
final class DimensionPhysicsData {
  /// `DIMENSION_PHYSICS_DATA`: the datapack values, by dimension id.
  static final Map<String, DimensionPhysics> dimensionPhysicsData = {};

  /// `DEFAULT_DIMENSION_PHYSICS_DATA`: the computed defaults, by dimension id.
  static final Map<String, DimensionPhysics> defaultDimensionPhysicsData = {};

  /// `of(level)`: the configured values, or the default.
  static DimensionPhysics of(SableLevel level) =>
      dimensionPhysicsData[level.dimensionId] ?? getDefault(level);

  /// `getDefault(level)`.
  static DimensionPhysics getDefault(SableLevel level, {int seaLevel = 64}) =>
      defaultDimensionPhysicsData.putIfAbsent(
        level.dimensionId,
        () => DimensionPhysics.createDefault(level, seaLevel: seaLevel),
      );

  /// `getGravity(level, pos, dest)`.
  static Vector3d getGravity(SableLevel level, [Vector3d? dest]) {
    final physics = of(level);
    final fallback = getDefault(level);
    final gravity = physics.baseGravity ?? fallback.baseGravity ?? DimensionPhysics.defaultGravity;
    return (dest ?? Vector3d()).set(gravity.$1, gravity.$2, gravity.$3);
  }

  /// `getAirPressure(level, pos)`.
  static double getAirPressure(SableLevel level, Vector3d pos) {
    final physics = of(level);
    final fallback = getDefault(level);
    final pressure = physics.basePressure ?? fallback.basePressure ?? DimensionPhysics.defaultPressure;
    final curve = physics.pressureFunction ?? fallback.pressureFunction;
    if (curve == null) return pressure;
    return pressure * curve.evaluateFunction(pos.y);
  }

  /// `getMagneticNorth(level)`.
  static (double, double, double) getMagneticNorth(SableLevel level) {
    final physics = of(level);
    final fallback = getDefault(level);
    return physics.magneticNorth ?? fallback.magneticNorth ?? DimensionPhysics.defaultMagneticNorth;
  }

  /// `getUniversalDrag(level)`.
  static double getUniversalDrag(SableLevel level) {
    final physics = of(level);
    final fallback = getDefault(level);
    return physics.universalDrag ?? fallback.universalDrag ?? DimensionPhysics.defaultUniversalDrag;
  }

  /// `addPhysicsWithPriority(key, newProperties)`: a higher priority wins.
  static void addPhysicsWithPriority(String dimensionId, DimensionPhysics newProperties) {
    final existing = dimensionPhysicsData[dimensionId];
    if (existing == null || newProperties.priority > existing.priority) {
      dimensionPhysicsData[dimensionId] = newProperties;
    }
  }

  /// `putPhysics(key, newProperties)`.
  static void putPhysics(String dimensionId, DimensionPhysics newProperties) =>
      dimensionPhysicsData[dimensionId] = newProperties;

  /// `clearPhysics()`.
  static void clearPhysics() => dimensionPhysicsData.clear();

  /// Forgets the computed defaults too (server shutdown).
  static void clearDefaults() => defaultDimensionPhysicsData.clear();

  /// `compilePacket()`: the configured values, in table order.
  static List<DimensionPhysics> compilePacket() => dimensionPhysicsData.values.toList(growable: false);
}
