// `BezierConnection` (pure): the curved track between two track block entities. Everything the
// server needs: resolution (length, handle length, radius, segment count, step lookup table),
// positions / normals / derivatives along the curve, iteration over the segments, the NBT and
// network forms, item costs and the rasterisation used to place fake tracks.
//
// Java -> Dart: `Iterable<Segment>` is [segments] (the class itself is iterable too);
// `float` arithmetic of the step table is reproduced with [toFloat]. The baked render transforms
// (`SegmentAngles`, `GirderAngles`) are client only and not ported. `spawnItems` /
// `spawnDestroyParticles` / `addItemsToPlayer` need the host and live in `track_host.dart`.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/common.dart';
import '../../core/byte_buf.dart';
import '../util/ctag.dart';
import 'track_block_entity_tilt.dart';
import 'track_level.dart';
import 'track_material.dart';
import 'track_shape.dart' show vnorm;

/// `AllBlocks.METAL_GIRDER`.
const String girderKey = 'create:metal_girder';

class BezierConnection {
  final Couple<Pos> bePositions;
  final Couple<Vec3> starts;
  final Couple<Vec3> axes;
  final Couple<Vec3> normals;
  Couple<int>? smoothing;
  final bool primary;
  final bool hasGirder;
  TrackMaterial trackMaterial;

  _Runtime? _lazyRuntime;

  BezierConnection(
    Couple<Pos> positions,
    this.starts,
    this.axes,
    this.normals,
    this.primary,
    bool girder,
    TrackMaterial material,
  ) : bePositions = positions,
      hasGirder = girder,
      trackMaterial = material;

  /// `secondary()`: the same curve seen from the other end.
  BezierConnection secondary() {
    final bezierConnection = BezierConnection(
      bePositions.swap(),
      starts.swap(),
      axes.swap(),
      normals.swap(),
      !primary,
      hasGirder,
      trackMaterial,
    );
    final s = smoothing;
    if (s != null) bezierConnection.smoothing = s.swap();
    return bezierConnection;
  }

  /// `clone()`.
  BezierConnection clone() {
    final out = BezierConnection(
      bePositions.copy(),
      starts.copy(),
      axes.copy(),
      normals.copy(),
      primary,
      hasGirder,
      trackMaterial,
    );
    final s = smoothing;
    if (s != null) out.smoothing = s.copy();
    return out;
  }

  static bool _coupleEqualsPos(Couple<Pos> a, Couple<Pos> b) => a.first == b.first && a.second == b.second;

  static bool _coupleEqualsVec(Couple<Vec3> a, Couple<Vec3> b) =>
      (a.first == b.first && a.second == b.second) ||
      (_closerThan(a.first, b.first, 1e-6) && _closerThan(a.second, b.second, 1e-6));

  static bool _closerThan(Vec3 a, Vec3 b, double distance) => (a - b).lengthSquared < distance * distance;

  /// `equalsSansMaterial(other)`.
  bool equalsSansMaterial(BezierConnection other) => _equalsSansMaterialInner(other) || _equalsSansMaterialInner(other.secondary());

  bool _equalsSansMaterialInner(BezierConnection other) =>
      identical(this, other) ||
      (_coupleEqualsPos(bePositions, other.bePositions) &&
          _coupleEqualsVec(starts, other.starts) &&
          _coupleEqualsVec(axes, other.axes) &&
          _coupleEqualsVec(normals, other.normals) &&
          hasGirder == other.hasGirder);

  /// `new BezierConnection(CompoundTag, BlockPos localTo)`.
  factory BezierConnection.fromTag(CTag compound, Pos localTo) {
    Couple<T> deserializeEach<T>(String key, T Function(CTag) f) {
      final list = compound.getCompoundList(key);
      return Couple<T>(f(list.isNotEmpty ? list[0] : CTag()), f(list.length > 1 ? list[1] : CTag()));
    }

    Vec3 readVec(CTag t) => t.getVec3('V');
    final positions = deserializeEach<Pos>('Positions', (t) => t.getBlockPos('Pos')).map((b) => b + localTo);
    final low = localTo.toVec3();
    final starts = deserializeEach<Vec3>('Starts', readVec).map((v) => v + low);
    final bc = BezierConnection(
      positions,
      starts,
      deserializeEach<Vec3>('Axes', readVec),
      deserializeEach<Vec3>('Normals', readVec),
      compound.getBoolean('Primary'),
      compound.getBoolean('Girder'),
      TrackMaterial.deserialize(compound.getString('Material')),
    );
    if (compound.contains('Smoothing')) {
      bc.smoothing = deserializeEach<int>('Smoothing', (t) => t.getInt('V'));
    }
    return bc;
  }

  /// `write(BlockPos localTo)`.
  CTag write(Pos localTo) {
    final tePositions = bePositions.map((b) => b - localTo);
    final low = localTo.toVec3();
    final startsLocal = starts.map((v) => v - low);

    CTag vecTag(Vec3 v) => CTag()..putVec3('V', v);
    List<CTag> serializeEach<T>(Couple<T> c, CTag Function(T) f) => [f(c.first), f(c.second)];

    final compound = CTag();
    compound.putBoolean('Girder', hasGirder);
    compound.putBoolean('Primary', primary);
    compound.putCompoundList(
      'Positions',
      serializeEach<Pos>(tePositions, (t) => CTag()..putBlockPos('Pos', t)),
    );
    compound.putCompoundList('Starts', serializeEach<Vec3>(startsLocal, vecTag));
    compound.putCompoundList('Axes', serializeEach<Vec3>(axes, vecTag));
    compound.putCompoundList('Normals', serializeEach<Vec3>(normals, vecTag));
    compound.putString('Material', getMaterial().id);
    final s = smoothing;
    if (s != null) {
      compound.putCompoundList('Smoothing', serializeEach<int>(s, (i) => CTag()..putInt('V', i)));
    }
    return compound;
  }

  /// `new BezierConnection(FriendlyByteBuf)`.
  factory BezierConnection.read(PacketReader buffer) {
    Couple<T> create<T>(T Function() f) => Couple<T>(f(), f());
    final positions = create<Pos>(buffer.readBlockPos);
    final starts = create<Vec3>(buffer.readVec3);
    final axes = create<Vec3>(buffer.readVec3);
    final normals = create<Vec3>(buffer.readVec3);
    final primary = buffer.readBool();
    final girder = buffer.readBool();
    final material = TrackMaterial.deserialize(buffer.readString());
    final bc = BezierConnection(positions, starts, axes, normals, primary, girder, material);
    if (buffer.readBool()) bc.smoothing = create<int>(buffer.readVarInt);
    return bc;
  }

  /// `write(FriendlyByteBuf)`.
  void writeTo(PacketWriter buffer) {
    bePositions.forEach(buffer.writeBlockPos);
    starts.forEach(buffer.writeVec3);
    axes.forEach(buffer.writeVec3);
    normals.forEach(buffer.writeVec3);
    buffer.writeBool(primary);
    buffer.writeBool(hasGirder);
    buffer.writeString(getMaterial().id);
    final s = smoothing;
    buffer.writeBool(s != null);
    if (s != null) s.forEach(buffer.writeVarInt);
  }

  /// `getKey()`: the position of the other end.
  Pos getKey() => bePositions.getSecond();

  bool isPrimary() => primary;

  /// `yOffsetAt(end)`.
  int yOffsetAt(Vec3 end) {
    final s = smoothing;
    if (s == null) return 0;
    if (TrackBlockEntityTilt.compareHandles(starts.getFirst(), end)) return s.getFirst();
    if (TrackBlockEntityTilt.compareHandles(starts.getSecond(), end)) return s.getSecond();
    return 0;
  }

  // Runtime information

  double getLength() => _resolve().length;

  /// `getStepLUT()`: float values.
  Float32List getStepLUT() => _resolve().stepLUT;

  int getSegmentCount() => _resolve().segments;

  /// `getPosition(t)`.
  Vec3 getPosition(double t) {
    final runtime = _resolve();
    return VecHelper.bezier(starts.getFirst(), starts.getSecond(), runtime.finish1, runtime.finish2, toFloat(t));
  }

  double getRadius() => _resolve().radius;

  double getHandleLength() => _resolve().handleLength;

  /// `getSegmentT(index)` (a float).
  double getSegmentT(int index) => _resolve().getSegmentT(index);

  /// `incrementT(currentT, distance)`.
  double incrementT(double currentT, double distance) {
    final runtime = _resolve();
    final dx =
        VecHelper.bezierDerivative(starts.getFirst(), starts.getSecond(), runtime.finish1, runtime.finish2, toFloat(currentT)).length /
        getLength();
    return currentT + distance / dx;
  }

  /// `getBounds()`.
  Aabb getBounds() => _resolve().bounds;

  /// `getNormal(t)`.
  Vec3 getNormal(double t) {
    final runtime = _resolve();
    final end1 = starts.getFirst();
    final end2 = starts.getSecond();
    final fn1 = normals.getFirst();
    final fn2 = normals.getSecond();
    final tf = toFloat(t);

    final derivative = vnorm(VecHelper.bezierDerivative(end1, end2, runtime.finish1, runtime.finish2, tf));
    final faceNormal = fn1 == fn2 ? fn1 : VecHelper.slerp(tf, fn1, fn2);
    final normal = vnorm(faceNormal.cross(derivative));
    return derivative.cross(normal);
  }

  /// `getDerivative(t)`: the (not normalised) derivative of the curve.
  Vec3 getDerivative(double t) {
    final runtime = _resolve();
    return VecHelper.bezierDerivative(starts.getFirst(), starts.getSecond(), runtime.finish1, runtime.finish2, toFloat(t));
  }

  _Runtime _resolve() => _lazyRuntime ??= _Runtime(starts, axes);

  /// `iterator()`: the segments of the curve, relative to the first block entity.
  Iterable<Segment> get segments => _iterate();

  Iterable<Segment> _iterate() sync* {
    final offset = bePositions.getFirst().toVec3() * -1 + (0.0, toFloat(3 / 16), 0.0);
    final runtime = _resolve();
    final end1 = starts.getFirst() + offset;
    final end2 = starts.getSecond() + offset;
    final finish1 = axes.getFirst() * runtime.handleLength + end1;
    final finish2 = axes.getSecond() * runtime.handleLength + end2;
    final faceNormal1 = normals.getFirst();
    final faceNormal2 = normals.getSecond();
    for (var index = 0; index <= runtime.segments; index++) {
      final t = runtime.getSegmentT(index);
      final segment = Segment();
      segment.index = index;
      segment.position = VecHelper.bezier(end1, end2, finish1, finish2, t);
      segment.derivative = vnorm(VecHelper.bezierDerivative(end1, end2, finish1, finish2, t));
      segment.faceNormal = faceNormal1 == faceNormal2 ? faceNormal1 : VecHelper.slerp(t, faceNormal1, faceNormal2);
      segment.normal = vnorm(segment.faceNormal.cross(segment.derivative));
      yield segment;
    }
  }

  int getGirderItemCost() => hasGirder ? getTrackItemCost() * 2 : 0;

  int getTrackItemCost() => (getSegmentCount() + 1) ~/ 2;

  /// `addItemsToPlayer(player)`: the track and girder items of the curve go to the player.
  void addItemsToPlayer(TrackPlacementPlayer player) {
    var tracks = getTrackItemCost();
    while (tracks > 0) {
      player.placeItemBackInInventory(getMaterial().getItemKey(), math.min(64, tracks));
      tracks -= 64;
    }
    var girders = getGirderItemCost();
    while (girders > 0) {
      player.placeItemBackInInventory(girderKey, math.min(64, girders));
      girders -= 64;
    }
  }

  /// `spawnItems(level)`: drops the items of the curve along it.
  void spawnItems(TrackLevel level) {
    if (!level.blockDropsEnabled) return;
    final origin = bePositions.getFirst().toVec3();
    for (final segment in segments) {
      if (segment.index % 2 != 0 || segment.index == getSegmentCount()) continue;
      final v = VecHelper.offsetRandomly(segment.position, level.random, toFloat(.125)) + origin;
      level.spawnItemEntity(v, getMaterial().getItemKey(), 1);
      if (!hasGirder) continue;
      for (var i = 0; i < 2; i++) {
        level.spawnItemEntity(v, girderKey, 1);
      }
    }
  }

  /// `spawnDestroyParticles(level)`.
  void spawnDestroyParticles(TrackLevel level) {
    final origin = bePositions.getFirst().toVec3();
    for (final segment in segments) {
      for (final offset in Iterate.positiveAndNegative) {
        final v = segment.position + segment.normal * (toFloat(14 / 16) * offset) + origin;
        level.sendBlockParticles(getMaterial().getBlockKey(), v);
        if (!hasGirder) continue;
        level.sendBlockParticles(girderKey, (v.x, v.y - toFloat(.5), v.z));
      }
    }
  }

  TrackMaterial getMaterial() => trackMaterial;

  void setMaterial(TrackMaterial material) => trackMaterial = material;

  /// `rasterise()`: the lowest rail height for each (x, z) the curve passes, in block entity
  /// local coordinates.
  Map<Pair<int, int>, double> rasterise() {
    final yLevels = <Pair<int, int>, double>{};
    final tePosition = bePositions.getFirst();
    final low = tePosition.toVec3();
    final up = (0.0, toFloat(3 / 16), 0.0);
    final end1 = starts.getFirst() - low + up;
    final end2 = starts.getSecond() - low + up;
    final axis1 = axes.getFirst();
    final axis2 = axes.getSecond();

    final handleLength = getHandleLength();
    final finish1 = axis1 * handleLength + end1;
    final finish2 = axis2 * handleLength + end2;

    final faceNormal1 = normals.getFirst();
    final faceNormal2 = normals.getSecond();

    final segCount = getSegmentCount();
    final lut = getStepLUT();
    final samples = List<Vec3>.filled(segCount, vec3Zero);

    for (var i = 0; i < segCount; i++) {
      final t = toFloat(toFloat(toFloat(i + 0.5) * lut[i]) / segCount).clamp(0.0, 1.0).toDouble();
      final result = VecHelper.bezier(end1, end2, finish1, finish2, t);
      final derivative = vnorm(VecHelper.bezierDerivative(end1, end2, finish1, finish2, t));
      final faceNormal = faceNormal1 == faceNormal2 ? faceNormal1 : VecHelper.slerp(t, faceNormal1, faceNormal2);
      final normal = vnorm(faceNormal.cross(derivative));
      final below = result + faceNormal * toFloat(-.25);
      final rail1 = below + normal * toFloat(.05);
      final rail2 = below - normal * toFloat(.05);
      final railMiddle = (rail1 + rail2) * .5;
      samples[i] = railMiddle;
    }

    final center = (end1 + end2) * 0.5;

    Pair<int, int>? prev;
    Pair<int, int>? prev2;
    Pair<int, int>? prev3;

    for (var i = 0; i < segCount; i++) {
      final railMiddle = samples[i];
      final pos = posContaining(railMiddle);
      final key = Pair<int, int>(pos.x, pos.z);
      final alreadyPresent = yLevels.containsKey(key);
      if (alreadyPresent && yLevels[key]! <= railMiddle.y) continue;
      yLevels[key] = railMiddle.y;
      if (alreadyPresent) continue;

      if (prev3 != null) {
        // Remove obsolete pixels
        final doubledViaPrev = _isLineDoubled(prev2!, prev!, key);
        final doubledViaPrev2 = _isLineDoubled(prev3, prev2, prev);
        final prevCloser = _diff(prev, center) > _diff(prev2, center);

        if (doubledViaPrev2 && (!doubledViaPrev || !prevCloser)) {
          yLevels.remove(prev2);
          prev2 = prev;
          prev = key;
          continue;
        } else if (doubledViaPrev && doubledViaPrev2 && prevCloser) {
          yLevels.remove(prev);
          prev = key;
          continue;
        }
      }

      prev3 = prev2;
      prev2 = prev;
      prev = key;
    }

    return yLevels;
  }

  static double _diff(Pair<int, int> pFrom, Vec3 to) {
    final dx = to.x - (pFrom.first + 0.5);
    final dy = to.y - to.y;
    final dz = to.z - (pFrom.second + 0.5);
    return dx * dx + dy * dy + dz * dz;
  }

  static bool _isLineDoubled(Pair<int, int> pFrom, Pair<int, int> pVia, Pair<int, int> pTo) {
    final diff1x = pVia.first - pFrom.first;
    final diff1z = pVia.second - pFrom.second;
    final diff2x = pTo.first - pVia.first;
    final diff2z = pTo.second - pVia.second;
    return diff1x.abs() + diff1z.abs() == 1 && diff2x.abs() + diff2z.abs() == 1 && diff1x != diff2x && diff1z != diff2z;
  }
}

/// `BezierConnection.Segment`.
class Segment {
  int index = 0;
  Vec3 position = vec3Zero;
  Vec3 derivative = vec3Zero;
  Vec3 faceNormal = vec3Zero;
  Vec3 normal = vec3Zero;
}

/// `BezierConnection.Runtime`: the values computed once from the end points and axes.
class _Runtime {
  late final Vec3 finish1;
  late final Vec3 finish2;
  late final double length;
  late final Float32List stepLUT;
  late final int segments;

  double radius = 0;
  double handleLength = 0;

  late final Aabb bounds;

  _Runtime(Couple<Vec3> starts, Couple<Vec3> axes) {
    final end1 = starts.getFirst();
    final end2 = starts.getSecond();
    final axis1 = vnorm(axes.getFirst());
    final axis2 = vnorm(axes.getSecond());

    _determineHandles(end1, end2, axis1, axis2);

    finish1 = axis1 * handleLength + end1;
    finish2 = axis2 * handleLength + end2;

    const scanCount = 16;

    length = _computeLength(finish1, finish2, end1, end2, scanCount);

    segments = (length * 2).toInt();
    stepLUT = Float32List(segments + 1);
    stepLUT[0] = 1;
    var combinedDistance = 0.0; // a float

    var bounds = Aabb.between(end1, end2);

    // determine step lut
    {
      var previous = end1;
      for (var i = 0; i <= segments; i++) {
        final t = toFloat(i / segments);
        final result = VecHelper.bezier(end1, end2, finish1, finish2, t);
        bounds = bounds.minmax(Aabb(result.x, result.y, result.z, result.x, result.y, result.z));
        if (i > 0) {
          combinedDistance = toFloat(combinedDistance + result.distanceTo(previous) / length);
          stepLUT[i] = toFloat(t / combinedDistance);
        }
        previous = result;
      }
    }

    this.bounds = bounds.inflate(toFloat(1.375));
  }

  static double _computeLength(Vec3 finish1, Vec3 finish2, Vec3 end1, Vec3 end2, int scanCount) {
    var length = 0.0;
    Vec3? previous = end1;
    for (var i = 0; i <= scanCount; i++) {
      final t = toFloat(i / scanCount);
      final result = VecHelper.bezier(end1, end2, finish1, finish2, t);
      if (previous != null) length += result.distanceTo(previous);
      previous = result;
    }
    return length;
  }

  double getSegmentT(int index) => index == segments ? 1 : toFloat(toFloat(index * stepLUT[index]) / segments);

  void _determineHandles(Vec3 end1, Vec3 end2, Vec3 axis1, Vec3 axis2) {
    final cross1 = axis1.cross((0.0, 1.0, 0.0));
    final cross2 = axis2.cross((0.0, 1.0, 0.0));

    radius = 0;
    final a1 = math.atan2(-axis2.z, -axis2.x);
    final a2 = math.atan2(axis1.z, axis1.x);
    var angle = a1 - a2;

    final circle = toFloat(2 * math.pi);
    angle = (angle + circle) % circle;
    if ((circle - angle).abs() < angle.abs()) angle = circle - angle;

    if (mthEqual(angle, 0)) {
      final intersect = VecHelper.intersect(end1, end2, axis1, cross2, Axis.y);
      if (intersect != null) {
        final t = intersect[0].abs();
        final u = intersect[1].abs();
        final min = math.min(t, u);
        final max = math.max(t, u);

        if (min > 1.2 && max / min > 1 && max / min < 3) {
          handleLength = max - min;
          return;
        }
      }

      handleLength = end2.distanceTo(end1) / 3;
      return;
    }

    final n = circle / angle;
    final factor = 4 / 3 * math.tan(math.pi / (2 * n));
    final intersect = VecHelper.intersect(end1, end2, cross1, cross2, Axis.y);

    if (intersect == null) {
      handleLength = end2.distanceTo(end1) / 3;
      return;
    }

    radius = intersect[1].abs();
    handleLength = radius * factor;
    if (mthEqual(handleLength, 0)) handleLength = 1;
  }
}
