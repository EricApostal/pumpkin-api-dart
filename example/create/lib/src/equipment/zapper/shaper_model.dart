// Port of `content/equipment/zapper/{PlacementPatterns}` and
// `.../terrainzapper/{Brush,CuboidBrush,SphereBrush,CylinderBrush,DynamicBrush,
// TerrainBrushes,TerrainTools,PlacementOptions,FlattenTool}`: the shape generation
// and the tools of the worldshaper. Pure; the world is reached through [ShaperWorld].
import 'dart:typed_data';

import '../model/dir.dart';

// ---------------------------------------------------------------------------------
// Enums (ordinals are the wire / component form: `CatnipStreamCodecBuilders.ofEnum`)
// ---------------------------------------------------------------------------------

/// `PlacementPatterns`.
enum PlacementPatterns {
  solid('solid'),
  checkered('checkered'),
  inverseCheckered('inverse_checkered'),
  chance25('chance25'),
  chance50('chance50'),
  chance75('chance75');

  const PlacementPatterns(this.serializedName);

  /// `Lang.asId(name())`.
  final String serializedName;

  static PlacementPatterns? bySerializedName(String s) {
    for (final p in values) {
      if (p.serializedName == s) return p;
    }
    return null;
  }

  /// `applyPattern`: removes the positions the pattern's filter selects. [nextBoolean]
  /// stands in for `RandomSource.nextBoolean` (evaluation order is kept).
  static void apply(List<P3> blocks, PlacementPatterns pattern, bool Function() nextBoolean) {
    bool Function(P3) filter = (_) => false;
    switch (pattern) {
      case chance25:
        filter = (p) => nextBoolean() || nextBoolean();
      case chance50:
        filter = (p) => nextBoolean();
      case chance75:
        filter = (p) => nextBoolean() && nextBoolean();
      case checkered:
        filter = (p) => (p.$1 + p.$2 + p.$3) % 2 == 0;
      case inverseCheckered:
        filter = (p) => (p.$1 + p.$2 + p.$3) % 2 != 0;
      case solid:
        break;
    }
    blocks.removeWhere(filter);
  }
}

/// `PlacementOptions`.
enum PlacementOptions {
  merged('merged'),
  attached('attached'),
  inserted('inserted');

  const PlacementOptions(this.serializedName);
  final String serializedName;
}

/// `TerrainTools`.
enum TerrainTools {
  fill('fill'),
  place('place'),
  replace('replace'),
  clear('clear'),
  overlay('overlay'),
  flatten('flatten');

  const TerrainTools(this.serializedName);
  final String serializedName;

  bool get requiresSelectedBlock => this != clear && this != flatten;

  /// `TerrainTools.isReplaceable(state)`.
  static bool isReplaceable(ShaperCell cell) => cell.replaceable;

  /// `run(level, targetPositions, facing, paintedState, data, player)`.
  Future<void> run(
    ShaperWorld world,
    List<P3> targets,
    Dir facing,
    Object? painted,
    ShaperBlockData? data,
  ) async {
    switch (this) {
      case clear:
        for (final p in targets) {
          await world.setAir(p);
        }
      case fill:
        for (final p in targets) {
          if (!isReplaceable(world.cell(p))) continue;
          await world.place(p, painted, data);
        }
      case flatten:
        await FlattenTool.apply(world, targets, facing);
      case overlay:
        for (var p in targets) {
          final toOverlay = world.cell(p);
          if (isReplaceable(toOverlay)) continue;
          if (toOverlay.state == painted) continue;
          p = p.up1;
          if (!isReplaceable(world.cell(p))) continue;
          await world.place(p, painted, data);
        }
      case place:
        for (final p in targets) {
          await world.place(p, painted, data);
        }
      case replace:
        for (final p in targets) {
          if (isReplaceable(world.cell(p))) continue;
          await world.place(p, painted, data);
        }
    }
  }
}

/// Extra block entity data copied to placed blocks (opaque to this layer).
typedef ShaperBlockData = Object;

/// What the tools need to know about a block position.
final class ShaperCell {
  /// Opaque identity of the full state (compared with `==`).
  final Object state;

  /// The block (without properties), compared for the dynamic brush's "same block" test.
  final String block;
  final bool replaceable;

  /// `getDestroySpeed(...) == -1`.
  final bool unbreakable;

  /// A liquid block (`instanceof LiquidBlock`).
  final bool liquid;

  /// `BlockHelper.hasBlockSolidSide(state, world, pos, dir)`, per direction.
  final bool Function(Dir side) hasSolidSide;

  const ShaperCell({
    required this.state,
    required this.block,
    required this.replaceable,
    this.unbreakable = false,
    this.liquid = false,
    this.hasSolidSide = _noSolidSide,
  });

  static bool _noSolidSide(Dir _) => false;
}

/// The world as the tools see it.
abstract interface class ShaperWorld {
  ShaperCell cell(P3 pos);

  /// `world.setBlockAndUpdate(pos, Blocks.AIR)`.
  Future<void> setAir(P3 pos);

  /// `world.setBlockAndUpdate(pos, painted)` followed by `ZapperItem.setBlockEntityData`.
  Future<void> place(P3 pos, Object? painted, ShaperBlockData? data);

  /// `world.setBlockAndUpdate(pos, state)` with a state that was read earlier.
  Future<void> setState(P3 pos, Object state);

  /// `state.getFluidState().createLegacyBlock()` of the block at [pos].
  Object fluidLegacyState(P3 pos);
}

// ---------------------------------------------------------------------------------
// Brushes
// ---------------------------------------------------------------------------------

/// `Brush`.
abstract class Brush {
  int param0 = 0, param1 = 0, param2 = 0;
  final int amtParams;

  Brush(this.amtParams);

  void set(int p0, int p1, int p2) {
    param0 = p0;
    param1 = p1;
    param2 = p2;
  }

  List<TerrainTools> get supportedTools => TerrainTools.values;

  TerrainTools redirectTool(TerrainTools tool) => tool;

  bool get hasPlacementOptions => true;
  bool get hasConnectivityOptions => false;

  int getMax(int paramIndex) => 0x7fffffff;
  int getMin(int paramIndex) => 0;

  int get(int paramIndex) => paramIndex == 0 ? param0 : (paramIndex == 1 ? param1 : param2);

  /// `getOffset(ray, face, option)`.
  P3 getOffset(V3 ray, Dir face, PlacementOptions option) => (0, 0, 0);

  /// `addToGlobalPositions`: appends the affected positions to [out].
  void addToGlobalPositions(ShaperWorld world, P3 target, Dir face, List<P3> out, TerrainTools used);
}

typedef V3 = (double, double, double);

/// `BlockPos.betweenClosed(min, max)` order: x fastest, then y, then z.
Iterable<P3> betweenClosed(P3 a, P3 b) sync* {
  final minX = a.$1 < b.$1 ? a.$1 : b.$1, maxX = a.$1 < b.$1 ? b.$1 : a.$1;
  final minY = a.$2 < b.$2 ? a.$2 : b.$2, maxY = a.$2 < b.$2 ? b.$2 : a.$2;
  final minZ = a.$3 < b.$3 ? a.$3 : b.$3, maxZ = a.$3 < b.$3 ? b.$3 : a.$3;
  for (var z = minZ; z <= maxZ; z++) {
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        yield (x, y, z);
      }
    }
  }
}

/// `ShapedBrush`.
abstract class ShapedBrush extends Brush {
  ShapedBrush(super.amt);

  List<P3>? get includedPositions;

  @override
  void addToGlobalPositions(ShaperWorld world, P3 target, Dir face, List<P3> out, TerrainTools used) {
    final included = includedPositions;
    if (included == null) return;
    for (final p in included) {
      out.add(target.plus(p));
    }
  }
}

/// `CuboidBrush`.
class CuboidBrush extends ShapedBrush {
  static const maxSize = 32;
  List<P3> _positions = [];

  CuboidBrush() : super(3);

  @override
  void set(int p0, int p1, int p2) {
    final update = param0 != p0 || param1 != p1 || param2 != p2;
    super.set(p0, p1, p2);
    if (update) {
      _positions = betweenClosed(
        ((p0 - 1) ~/ -2, (p1 - 1) ~/ -2, (p2 - 1) ~/ -2),
        (p0 ~/ 2, p1 ~/ 2, p2 ~/ 2),
      ).toList();
    }
  }

  @override
  int getMin(int paramIndex) => 1;

  @override
  int getMax(int paramIndex) => maxSize;

  @override
  P3 getOffset(V3 ray, Dir face, PlacementOptions option) {
    if (option == PlacementOptions.merged) return (0, 0, 0);
    final offset = option == PlacementOptions.attached ? (!face.positive ? 2 : 1) : 0;
    final x = (param0 + (param0 == 0 ? 0 : offset)) ~/ 2;
    final y = (param1 + (param1 == 0 ? 0 : offset)) ~/ 2;
    final z = (param2 + (param2 == 0 ? 0 : offset)) ~/ 2;
    final n = face.axis.choose(x, y, z) * (option == PlacementOptions.attached ? 1 : -1);
    return (0, 0, 0).rel(face, n);
  }

  @override
  List<P3>? get includedPositions => _positions;
}

/// `SphereBrush`.
class SphereBrush extends ShapedBrush {
  static const maxRadius = 10;
  final Map<int, List<P3>> _cache = {};

  SphereBrush() : super(1) {
    for (var i = 0; i <= maxRadius; i++) {
      _cache[i] = [
        for (final p in betweenClosed((-i - 1, -i - 1, -i - 1), (i + 1, i + 1, i + 1)))
          if (len3(p.$1.toDouble(), p.$2.toDouble(), p.$3.toDouble()) < i + 0.5) p,
      ];
    }
  }

  @override
  P3 getOffset(V3 ray, Dir face, PlacementOptions option) {
    if (option == PlacementOptions.merged) return (0, 0, 0);
    final offset = option == PlacementOptions.attached ? 0 : -1;
    final r = param0 + 1 + offset;
    return (0, 0, 0).rel(face, r * (option == PlacementOptions.attached ? 1 : -1));
  }

  @override
  int getMax(int paramIndex) => maxRadius;

  @override
  List<P3>? get includedPositions => _cache[param0];
}

/// `CylinderBrush`.
class CylinderBrush extends ShapedBrush {
  static const maxRadius = 8;
  static const maxHeight = 8;

  /// Java's `.42f` as a double.
  static const _radiusSlack = 0.41999998688697815;
  final Map<(int, int), List<P3>> _cache = {};

  CylinderBrush() : super(2) {
    for (var i = 0; i <= maxRadius; i++) {
      final positions = [
        for (final p in betweenClosed((-i - 1, 0, -i - 1), (i + 1, 0, i + 1)))
          if (len3(p.$1.toDouble(), 0, p.$3.toDouble()) < i + _radiusSlack) p,
      ];
      for (var h = 0; h <= maxHeight; h++) {
        final stacked = <P3>[];
        for (var layer = 0; layer < h; layer++) {
          final yOffset = layer - h ~/ 2;
          for (final p in positions) {
            stacked.add((p.$1, p.$2 + yOffset, p.$3));
          }
        }
        _cache[(i, h)] = stacked;
      }
    }
  }

  @override
  P3 getOffset(V3 ray, Dir face, PlacementOptions option) {
    if (option == PlacementOptions.merged) return (0, 0, 0);
    final offset = option == PlacementOptions.attached ? 0 : -1;
    final negative = !face.positive;
    final yOffset = option == PlacementOptions.attached ? (negative ? 1 : 2) : (negative ? 0 : -1);
    final r = param0 + 1 + offset;
    final y = (param1 + (param1 == 0 ? 0 : yOffset)) ~/ 2;
    return (0, 0, 0).rel(face, (face.axis.isVertical ? y : r) * (option == PlacementOptions.attached ? 1 : -1));
  }

  @override
  int getMax(int paramIndex) => paramIndex == 0 ? maxRadius : maxHeight;

  @override
  int getMin(int paramIndex) => paramIndex == 0 ? 0 : 1;

  @override
  List<P3>? get includedPositions => _cache[(param0, param1)];
}

/// `DynamicBrush` (the `Surface` and `Cluster` brushes).
class DynamicBrush extends Brush {
  static const maxRadius = 10;
  final bool surface;

  DynamicBrush(this.surface) : super(1);

  @override
  List<TerrainTools> get supportedTools => surface
      ? const [TerrainTools.overlay, TerrainTools.replace, TerrainTools.clear]
      : const [TerrainTools.replace, TerrainTools.clear];

  @override
  bool get hasPlacementOptions => false;

  @override
  bool get hasConnectivityOptions => true;

  @override
  int getMax(int paramIndex) => maxRadius;

  @override
  int getMin(int paramIndex) => 1;

  @override
  TerrainTools redirectTool(TerrainTools tool) => tool == TerrainTools.overlay ? TerrainTools.place : tool;

  @override
  void addToGlobalPositions(ShaperWorld world, P3 target, Dir face, List<P3> out, TerrainTools used) {
    final searchDiagonals = param1 == 0;
    final fuzzy = param2 == 0;
    final replace = used != TerrainTools.overlay;
    final searchRange = param0;
    final visited = <P3>{};
    final frontier = <P3>[];
    final state = world.cell(target);
    final offsets = <P3>[];
    for (var x = -1; x <= 1; x++) {
      for (var y = -1; y <= 1; y++) {
        for (var z = -1; z <= 1; z++) {
          if (x.abs() + y.abs() + z.abs() < 2 || searchDiagonals) {
            if (face.axis.choose(x, y, z) == 0 || !surface) offsets.add((x, y, z));
          }
        }
      }
    }
    final startPos = replace ? target : target.rel(face);
    var head = 0;
    frontier.add(startPos);
    while (head < frontier.length) {
      final current = frontier[head++];
      if (!visited.add(current)) continue;
      if (!current.within(startPos, searchRange.toDouble())) continue;

      if (replace) {
        final toReplace = world.cell(current);
        final above = world.cell(current.rel(face));
        if (toReplace.unbreakable) continue;
        if (toReplace.block != state.block && !fuzzy) continue;
        if (toReplace.replaceable) continue;
        if (above.hasSolidSide(face.opposite) && surface) continue;
        out.add(current);
        for (final o in offsets) {
          frontier.add(current.plus(o));
        }
        continue;
      }

      final placeAt = world.cell(current);
      final placeOn = world.cell(current.rel(face.opposite));
      if (placeOn.replaceable) continue;
      if (placeOn.block != state.block && !fuzzy) continue;
      if (!placeAt.replaceable) continue;
      out.add(current);
      for (final o in offsets) {
        frontier.add(current.plus(o));
      }
    }
  }
}

/// `TerrainBrushes`.
enum TerrainBrushes {
  cuboid('cuboid'),
  sphere('sphere'),
  cylinder('cylinder'),
  surface('surface'),
  cluster('cluster');

  const TerrainBrushes(this.serializedName);
  final String serializedName;

  /// The shared brush instance (as the Java enum holds one per constant).
  Brush get brush => _brushes.putIfAbsent(this, _create);

  Brush _create() => switch (this) {
    TerrainBrushes.cuboid => CuboidBrush(),
    TerrainBrushes.sphere => SphereBrush(),
    TerrainBrushes.cylinder => CylinderBrush(),
    TerrainBrushes.surface => DynamicBrush(true),
    TerrainBrushes.cluster => DynamicBrush(false),
  };

  static final Map<TerrainBrushes, Brush> _brushes = {};
}

// ---------------------------------------------------------------------------------
// FlattenTool
// ---------------------------------------------------------------------------------

/// `FlattenTool`.
abstract final class FlattenTool {
  /// Gaussian with sigma = 1.
  static const List<List<double>> kernel = [
    [0.003765, 0.015019, 0.023792, 0.015019, 0.003765],
    [0.015019, 0.059912, 0.094907, 0.059912, 0.015019],
    [0.023792, 0.094907, 0.150342, 0.094907, 0.023792],
    [0.015019, 0.059912, 0.094907, 0.059912, 0.015019],
    [0.003765, 0.015019, 0.023792, 0.015019, 0.003765],
  ];

  static const intMin = -2147483648;
  static const intMax = 2147483647;

  /// `applyKernel`. The Java sums `float`s; [_f32] rounds to single precision after
  /// each operation so the integer result matches.
  static List<List<int>> applyKernel(List<List<int>> values) {
    final result = List.generate(values.length, (_) => List.filled(values[0].length, 0));
    for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < values[i].length; j++) {
        final value = values[i][j];
        var newValue = 0.0;
        for (var io = -2; io <= 2; io++) {
          for (var jo = -2; jo <= 2; jo++) {
            final it = i + io, jt = j + jo;
            int ref;
            if (it < 0 || it >= values.length || jt < 0 || jt >= values[0].length) {
              ref = value;
            } else {
              ref = values[it][jt];
            }
            if (ref == intMin) ref = value;
            newValue = _f32(newValue + _f32(_f32(kernel[io + 2][jo + 2]) * ref));
          }
        }
        result[i][j] = (_f32(newValue + 0.5)).floor();
      }
    }
    return result;
  }

  static double _f32(double v) => _roundToFloat(v);

  static (int, int) _coords(P3 p, Dir facing) => switch (facing.axis) {
    Ax.x => (p.$3, p.$2),
    Ax.y => (p.$1, p.$3),
    Ax.z => (p.$1, p.$2),
  };

  static Future<void> apply(ShaperWorld world, List<P3> targets, Dir facing) async {
    final surfaces = <P3>[];
    final heightMap = <(int, int), int>{};
    final offset = facing.step;
    var minEntry = intMax, minC1 = intMax, minC2 = intMax;
    var maxEntry = intMin, maxC1 = intMin, maxC2 = intMin;

    for (var p in targets) {
      final coords = _coords(p, facing);
      final belowSurface = world.cell(p);
      minC1 = coords.$1 < minC1 ? coords.$1 : minC1;
      minC2 = coords.$2 < minC2 ? coords.$2 : minC2;
      maxC1 = coords.$1 > maxC1 ? coords.$1 : maxC1;
      maxC2 = coords.$2 > maxC2 ? coords.$2 : maxC2;

      if (TerrainTools.isReplaceable(belowSurface)) {
        heightMap.putIfAbsent(coords, () => intMin);
        continue;
      }
      p = p.rel(facing);
      final surface = world.cell(p);
      if (!TerrainTools.isReplaceable(surface)) {
        if (!heightMap.containsKey(coords) || heightMap[coords] == intMin) heightMap[coords] = intMax;
        continue;
      }
      surfaces.add(p);
      final coordinate = facing.axis.choose(p.$1, p.$2, p.$3);
      final existing = heightMap[coords];
      if (existing == null || existing == intMax || existing == intMin || existing * offset < coordinate * offset) {
        heightMap[coords] = coordinate;
        if (coordinate > maxEntry) maxEntry = coordinate;
        if (coordinate < minEntry) minEntry = coordinate;
      }
    }
    if (surfaces.isEmpty) return;

    var heightArray = List.generate(
      maxC1 - minC1 + 1,
      (i) => List.generate(maxC2 - minC2 + 1, (j) {
        final height = heightMap[(minC1 + i, minC2 + j)];
        if (height == null) return intMin;
        if (height == intMax) return offset == 1 ? maxEntry + 2 : minEntry - 2;
        if (height == intMin) return offset == 1 ? minEntry - 2 : maxEntry + 2;
        return height;
      }),
    );
    heightArray = applyKernel(heightArray);

    for (var p in surfaces) {
      final coords = _coords(p, facing);
      var surfaceCoord = facing.axis.choose(p.$1, p.$2, p.$3) * offset;
      final targetCoord = heightArray[coords.$1 - minC1][coords.$2 - minC2] * offset;
      if (surfaceCoord == targetCoord) continue;

      final blockState = world.cell(p);
      var timeOut = 1000;
      // Lower surface
      while (surfaceCoord > targetCoord) {
        final below = p.rel(facing.opposite);
        await world.setState(below, blockState.state);
        await world.setState(p, world.fluidLegacyState(p));
        p = p.rel(facing.opposite);
        surfaceCoord--;
        if (timeOut-- <= 0) break;
      }
      // Raise surface
      while (surfaceCoord < targetCoord) {
        final above = p.rel(facing);
        if (!blockState.liquid) await world.setState(above, blockState.state);
        await world.setState(p, world.cell(p.rel(facing.opposite)).state);
        p = p.rel(facing);
        surfaceCoord++;
        if (timeOut-- <= 0) break;
      }
    }
  }
}

final Float32List _f32buf = Float32List(1);

/// Rounds a double to the nearest IEEE single.
double _roundToFloat(double v) {
  _f32buf[0] = v;
  return _f32buf[0];
}
