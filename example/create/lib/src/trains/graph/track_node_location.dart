// `TrackNodeLocation` and `DiscoveredLocation` (pure). A node location is a point of the doubled
// block grid (x and z in half blocks, y in blocks * 2) plus a pixel offset and a dimension.
//
// Java -> Dart: `extends Vec3i` -> fields [x], [y], [z] and `getX()`..; `ResourceKey<Level>` ->
// world id [String]; `in(level)` (`in` is a Dart keyword) -> [inDimension] / [in_].
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/data.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../track/bezier_connection.dart';
import '../track/track_material.dart';
import '../util/ctag.dart';
import 'dimension_palette.dart';

/// `Math.round(double)` (floor(x + 1/2), not Dart's round half away from zero).
int javaRound(double x) {
  final f = x.floor();
  return x - f >= 0.5 ? f + 1 : f;
}

class TrackNodeLocation {
  final int x;
  final int y;
  final int z;
  String dimension = overworldId;
  int yOffsetPixels = 0;

  /// `new TrackNodeLocation(x, y, z)` from a world position.
  TrackNodeLocation(double px, double py, double pz)
    : x = javaRound(px * 2),
      y = py.floor() * 2,
      z = javaRound(pz * 2);

  /// `new TrackNodeLocation(Vec3)`.
  TrackNodeLocation.fromVec(Vec3 vec) : this(vec.$1, vec.$2, vec.$3);

  /// `new TrackNodeLocation(BlockPos)` of `fromPackedPos`: the raw grid coordinates.
  TrackNodeLocation.packed(this.x, this.y, this.z);

  int getX() => x;
  int getY() => y;
  int getZ() => z;

  /// `in(level)` / `in(dimension)`.
  TrackNodeLocation inDimension(String dimension) {
    this.dimension = dimension;
    return this;
  }

  /// Alias of [inDimension] (`in` is a keyword in Dart).
  TrackNodeLocation in_(String dimension) => inDimension(dimension);

  Vec3 getLocation() => (x / 2.0, y / 2.0 + yOffsetPixels / 16.0, z / 2.0);

  String getDimension() => dimension;

  @override
  bool operator ==(Object other) =>
      other is TrackNodeLocation && equalsIgnoreDim(other) && other.dimension == dimension;

  bool equalsIgnoreDim(Object other) =>
      other is TrackNodeLocation && other.x == x && other.y == y && other.z == z && other.yOffsetPixels == yOffsetPixels;

  @override
  int get hashCode => _int32((y + ((z + yOffsetPixels * 31) * 31 + dimension.hashCode) * 31) * 31 + x);

  static int _int32(int v) => v.toSigned(32);

  CTag write(DimensionPalette? dimensions) {
    final c = CTag();
    c.putBlockPos('Pos', (x, y, z));
    if (dimensions != null) c.putInt('D', dimensions.encode(dimension));
    if (yOffsetPixels != 0) c.putInt('YO', yOffsetPixels);
    return c;
  }

  static TrackNodeLocation read(CTag tag, DimensionPalette? dimensions) {
    final p = tag.contains('Pos') ? tag.getBlockPos('Pos') : (tag.getInt('X'), tag.getInt('Y'), tag.getInt('Z'));
    final location = TrackNodeLocation.packed(p.$1, p.$2, p.$3);
    if (dimensions != null) location.dimension = dimensions.decode(tag.getInt('D'));
    location.yOffsetPixels = tag.getInt('YO');
    return location;
  }

  /// `send(buffer, dimensions)`.
  void send(PacketWriter buffer, DimensionPalette dimensions) {
    buffer.writeVarInt(x);
    buffer.writeShort(y);
    buffer.writeVarInt(z);
    buffer.writeVarInt(yOffsetPixels);
    buffer.writeVarInt(dimensions.encode(dimension));
  }

  static TrackNodeLocation receive(PacketReader buffer, DimensionPalette dimensions) {
    final x = buffer.readVarInt();
    final y = buffer.readShort();
    final z = buffer.readVarInt();
    final location = TrackNodeLocation.packed(x, y, z);
    location.yOffsetPixels = buffer.readVarInt();
    location.dimension = dimensions.decode(buffer.readVarInt());
    return location;
  }

  Set<Pos> allAdjacent() {
    final set = <Pos>{};
    final vec3 = getLocation() - (0.0, yOffsetPixels / 16.0, 0.0);
    const step = 1 / 8.0;
    for (final dx in Iterate.positiveAndNegative) {
      for (final dy in Iterate.positiveAndNegative) {
        for (final dz in Iterate.positiveAndNegative) {
          set.add(posContaining(vec3 + (dx * step, dy * step, dz * step)));
        }
      }
    }
    return set;
  }

  @override
  String toString() => 'TrackNodeLocation($x, $y, $z, yo=$yOffsetPixels, $dimension)';
}

class DiscoveredLocation extends TrackNodeLocation {
  BezierConnection? turn;
  bool _forceNode = false;
  Vec3? direction;
  Vec3? normal;
  TrackMaterial? materialAValue;
  TrackMaterial? materialBValue;

  /// `new DiscoveredLocation(level, x, y, z)`; [dimension] is the world id.
  DiscoveredLocation(String dimension, double x, double y, double z) : super(x, y, z) {
    inDimension(dimension);
  }

  /// `new DiscoveredLocation(dimension, vec)` / `(level, vec)`.
  DiscoveredLocation.fromVec(String dimension, Vec3 vec) : super.fromVec(vec) {
    inDimension(dimension);
  }

  /// `materialA(material)` (the field of Java is [materialAValue]).
  DiscoveredLocation materialA(TrackMaterial material) {
    materialAValue = material;
    return this;
  }

  DiscoveredLocation materialB(TrackMaterial material) {
    materialBValue = material;
    return this;
  }

  TrackMaterial? getMaterialA() => materialAValue;

  TrackMaterial? getMaterialB() => materialBValue;

  /// `materials(a, b)`.
  DiscoveredLocation materials(TrackMaterial materialA, TrackMaterial materialB) {
    materialAValue = materialA;
    materialBValue = materialB;
    return this;
  }

  DiscoveredLocation viaTurn(BezierConnection? turn) {
    this.turn = turn;
    if (turn != null) forceNode();
    return this;
  }

  DiscoveredLocation forceNode() {
    _forceNode = true;
    return this;
  }

  DiscoveredLocation withNormal(Vec3? normal) {
    this.normal = normal;
    return this;
  }

  DiscoveredLocation withYOffset(int yOffsetPixels) {
    this.yOffsetPixels = yOffsetPixels;
    return this;
  }

  DiscoveredLocation withDirection(Vec3? direction) {
    this.direction = direction?.normalized;
    return this;
  }

  bool connectedViaTurn() => turn != null;

  BezierConnection? getTurn() => turn;

  bool shouldForceNode() => _forceNode;

  bool differentMaterials() => materialAValue != materialBValue;

  bool notInLineWith(Vec3 direction) {
    final d = this.direction;
    return d != null && math.max(direction.dot(d), direction.dot(d * -1)) < 7 / 8.0;
  }

  Vec3? getDirection() => direction;
}
