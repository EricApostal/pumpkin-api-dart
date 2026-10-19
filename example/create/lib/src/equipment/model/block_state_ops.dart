// Block states as plain data (block key + property map) and the property based
// rotate / mirror / cycle operations the symmetry wand and the wrench need. Pure.
//
// Vanilla implements `BlockState.rotate/mirror` per block class; here the same
// results are derived from the property names every vanilla (and Create) block uses
// (`facing`, `axis`, `north/east/south/west`, `rotation`, `hinge`, stairs `shape`...).
// This is a faithful port of the behaviours for the common shapes, not of every
// block class.
import 'dir.dart';

/// `net.minecraft.world.level.block.Rotation`.
enum Rot {
  none,
  clockwise90,
  clockwise180,
  counterclockwise90;

  Rot get inverse => switch (this) {
    Rot.none => Rot.none,
    Rot.clockwise90 => Rot.counterclockwise90,
    Rot.clockwise180 => Rot.clockwise180,
    Rot.counterclockwise90 => Rot.clockwise90,
  };

  int get quarterTurns => switch (this) {
    Rot.none => 0,
    Rot.clockwise90 => 1,
    Rot.clockwise180 => 2,
    Rot.counterclockwise90 => 3,
  };

  /// `Rotation.rotate(Direction)`: horizontals only, up/down are unchanged.
  Dir rotateDir(Dir d) {
    if (d.axis == Ax.y) return d;
    var r = d;
    for (var i = 0; i < quarterTurns; i++) {
      r = r.clockWise;
    }
    return r;
  }

  /// `Rotation.rotate(int rotation, int rotationCount)`.
  int rotateInt(int value, int count) => switch (this) {
    Rot.none => value,
    Rot.clockwise90 => (value + count ~/ 4) % count,
    Rot.clockwise180 => (value + count ~/ 2) % count,
    Rot.counterclockwise90 => (value + count ~/ 4 * 3) % count,
  };
}

/// `net.minecraft.world.level.block.Mirror`.
enum Mir {
  none,

  /// Mirrors along Z (north <-> south).
  leftRight,

  /// Mirrors along X (east <-> west).
  frontBack;

  /// `Mirror.getRotation(Direction)`.
  Rot rotationFor(Dir d) => switch (this) {
    Mir.leftRight => d.axis == Ax.z ? Rot.clockwise180 : Rot.none,
    Mir.frontBack => d.axis == Ax.x ? Rot.clockwise180 : Rot.none,
    Mir.none => Rot.none,
  };

  /// `Mirror.mirror(int rotation, int rotationCount)`.
  int mirrorInt(int rotation, int count) {
    final i = count ~/ 2;
    final j = rotation > i ? rotation - count : rotation;
    return switch (this) {
      Mir.leftRight => (count - j) % count,
      Mir.frontBack => (i - j + count) % count,
      Mir.none => rotation,
    };
  }
}

/// A block state: the block key and its property values.
final class BState {
  final String block;
  final Map<String, String> props;

  const BState(this.block, [this.props = const {}]);

  String? operator [](String name) => props[name];

  bool has(String name) => props.containsKey(name);

  BState set(String name, String value) => BState(block, {...props, name: value});

  Dir? dir(String name) => props[name] == null ? null : Dir.parse(props[name]!);

  @override
  bool operator ==(Object other) =>
      other is BState && other.block == block && other.props.length == props.length && _sameProps(other.props);

  bool _sameProps(Map<String, String> o) {
    for (final e in props.entries) {
      if (o[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(block, Object.hashAllUnordered(props.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => props.isEmpty ? block : '$block[${props.entries.map((e) => '${e.key}=${e.value}').join(',')}]';
}

/// Rotate / mirror / flip operations on [BState]s.
abstract final class BlockStateOps {
  static const _sides = ['north', 'east', 'south', 'west'];

  static BState rotate(BState s, Rot r) {
    if (r == Rot.none) return s;
    var props = Map<String, String>.of(s.props);
    final facing = s.dir('facing');
    if (facing != null) props['facing'] = r.rotateDir(facing).name;
    final axis = s['axis'];
    if (axis != null && (axis == 'x' || axis == 'z') && (r == Rot.clockwise90 || r == Rot.counterclockwise90)) {
      props['axis'] = axis == 'x' ? 'z' : 'x';
    }
    final hAxis = s['horizontal_axis'];
    if (hAxis != null && (r == Rot.clockwise90 || r == Rot.counterclockwise90)) {
      props['horizontal_axis'] = hAxis == 'x' ? 'z' : 'x';
    }
    if (s.has('north') && s.has('east') && s.has('south') && s.has('west')) {
      // `new side = old side rotated back`: NORTH takes WEST for CLOCKWISE_90.
      final back = r.inverse.quarterTurns;
      for (var i = 0; i < 4; i++) {
        props[_sides[i]] = s.props[_sides[(i + back) % 4]]!;
      }
    }
    final rotation = int.tryParse(s['rotation'] ?? '');
    if (rotation != null && s.has('rotation')) props['rotation'] = r.rotateInt(rotation, 16).toString();
    final shape = s['shape'];
    if (shape != null && _railShapes.containsKey(shape)) props['shape'] = _rotateRail(shape, r);
    return BState(s.block, props);
  }

  static const _railShapes = <String, int>{
    'north_south': 0,
    'east_west': 1,
    'ascending_east': 2,
    'ascending_west': 3,
    'ascending_north': 4,
    'ascending_south': 5,
    'south_east': 6,
    'south_west': 7,
    'north_west': 8,
    'north_east': 9,
  };

  static String _rotateRail(String shape, Rot r) {
    var cur = shape;
    for (var i = 0; i < r.quarterTurns; i++) {
      cur = _railCw[cur] ?? cur;
    }
    return cur;
  }

  static const _railCw = <String, String>{
    'north_south': 'east_west',
    'east_west': 'north_south',
    'ascending_east': 'ascending_south',
    'ascending_south': 'ascending_west',
    'ascending_west': 'ascending_north',
    'ascending_north': 'ascending_east',
    'south_east': 'south_west',
    'south_west': 'north_west',
    'north_west': 'north_east',
    'north_east': 'south_east',
  };

  static BState mirror(BState s, Mir m) {
    if (m == Mir.none) return s;
    // Stairs: mirror swaps the corner handedness when the facing is across the mirror.
    if (s.has('facing') && s.has('half') && s.has('shape') && s['shape']!.contains('_')) {
      final d = s.dir('facing')!;
      if ((m == Mir.leftRight && d.axis == Ax.z) || (m == Mir.frontBack && d.axis == Ax.x)) {
        final shape = s['shape']!;
        final swapped = switch (shape) {
          'inner_left' => 'inner_right',
          'inner_right' => 'inner_left',
          'outer_left' => 'outer_right',
          'outer_right' => 'outer_left',
          _ => null,
        };
        if (swapped != null) return s.set('shape', swapped);
        return rotate(s, Rot.clockwise180);
      }
      return s;
    }
    final props = Map<String, String>.of(s.props);
    final d = s.dir('facing');
    if (d != null) props['facing'] = m.rotationFor(d).rotateDir(d).name;
    if (s.has('hinge')) props['hinge'] = s['hinge'] == 'left' ? 'right' : 'left';
    if (s.has('north') && s.has('east') && s.has('south') && s.has('west')) {
      if (m == Mir.leftRight) {
        props['north'] = s.props['south']!;
        props['south'] = s.props['north']!;
      } else {
        props['east'] = s.props['west']!;
        props['west'] = s.props['east']!;
      }
    }
    final rotation = int.tryParse(s['rotation'] ?? '');
    if (rotation != null) props['rotation'] = m.mirrorInt(rotation, 16).toString();
    final shape = s['shape'];
    if (shape != null && _railShapes.containsKey(shape)) props['shape'] = _mirrorRail(shape, m);
    return BState(s.block, props);
  }

  static String _mirrorRail(String shape, Mir m) {
    // Mirror.LEFT_RIGHT swaps north <-> south, FRONT_BACK swaps east <-> west.
    String swap(String s) => m == Mir.leftRight
        ? s.replaceAll('north', '#').replaceAll('south', 'north').replaceAll('#', 'south')
        : s.replaceAll('east', '#').replaceAll('west', 'east').replaceAll('#', 'west');
    return swap(shape);
  }

  /// `SymmetryMirror.flipY`: `half` cycles; the first facing-like property that
  /// points up/down is inverted.
  static BState flipY(BState s) {
    final half = s['half'];
    if (half != null) {
      return s.set('half', switch (half) {
        'top' => 'bottom',
        'bottom' => 'top',
        'upper' => 'lower',
        'lower' => 'upper',
        _ => half,
      });
    }
    for (final e in s.props.entries) {
      if (e.value == 'down') return s.set(e.key, 'up');
      if (e.value == 'up') return s.set(e.key, 'down');
    }
    return s;
  }

  /// `BlockState.cycle(property)` for a property with the given value order.
  static BState cycle(BState s, String property, List<String> values) {
    final cur = s[property];
    if (cur == null) return s;
    final i = values.indexOf(cur);
    return s.set(property, values[(i + 1) % values.length]);
  }
}
