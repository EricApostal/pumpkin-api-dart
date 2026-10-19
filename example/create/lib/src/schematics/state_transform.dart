// Rotating and mirroring block states (pure): what `BlockState.rotate(Rotation)` and
// `BlockState.mirror(Mirror)` do for vanilla blocks and for Create's blocks that follow the same
// property conventions (`facing`, `axis`, `rotation`, `north/east/south/west`, rail `shape`, stair
// `shape`, door `hinge`, crafter `orientation`). `StructureTemplate` placement mirrors first and
// then rotates ([transformState]).
//
// Blocks with a rotation that depends on more than their properties (Create's belts and a few
// others) keep their state; that is the one known gap compared to the Java blocks.
import '../api/block_state.dart';
import '../common/direction.dart';

const List<String> _sides = ['north', 'east', 'south', 'west'];

/// The state after `mirror` and then `rotation`, the order of `StructureTemplate.placeInWorld`.
BState transformState(BState state, BlockMirror mirror, BlockRotation rotation) =>
    rotateState(mirrorState(state, mirror), rotation);

/// `BlockState.rotate(Rotation)`.
BState rotateState(BState s, BlockRotation r) {
  if (r == BlockRotation.none || s.props.isEmpty) return s;
  var props = s.props;
  Map<String, String> changed = {};

  // facing (6 directions or horizontal)
  final facing = s['facing'];
  if (facing != null) {
    final d = Direction.byName(facing);
    if (d != null && !_noFacingRotation(s)) changed['facing'] = r.rotate(d).serializedName;
  }

  // axis: only the horizontal axes swap on a quarter turn
  final axis = s['axis'];
  if (axis != null && (r == BlockRotation.clockwise90 || r == BlockRotation.counterclockwise90)) {
    if (axis == 'x') changed['axis'] = 'z';
    if (axis == 'z') changed['axis'] = 'x';
  }

  // rotation 0..15
  final rotation = s['rotation'];
  if (rotation != null) {
    final v = int.tryParse(rotation);
    if (v != null && v >= 0 && v < 16) changed['rotation'] = '${r.rotateInt(v, 16)}';
  }

  // north / east / south / west carry a value per side (fences, walls, redstone, vines, panes)
  if (_sides.every(s.has)) {
    for (final side in _sides) {
      final from = Direction.byName(side)!;
      changed[r.rotate(from).serializedName] = props[side]!;
    }
  }

  // rail shapes
  final shape = s['shape'];
  if (shape != null && _railShapes.contains(shape)) {
    changed['shape'] = _rotateRail(shape, r);
  }

  // crafter orientation
  final orientation = s['orientation'];
  if (orientation != null) {
    final o = _parseOrientation(orientation);
    if (o != null) changed['orientation'] = '${r.rotate(o.$1).serializedName}_${r.rotate(o.$2).serializedName}';
  }

  if (changed.isEmpty) return s;
  props = {...props, ...changed};
  return BState(s.key, props);
}

/// `BlockState.mirror(Mirror)`.
BState mirrorState(BState s, BlockMirror m) {
  if (m == BlockMirror.none || s.props.isEmpty) return s;

  final facing = s['facing'];
  final shape = s['shape'];

  // Stairs mirror their corner shapes.
  if (facing != null && shape != null && _stairShapes.contains(shape) && s.has('half')) {
    final d = Direction.byName(facing);
    if (d != null) {
      final onMirroredAxis = (m == BlockMirror.leftRight && d.axis == Axis.z) || (m == BlockMirror.frontBack && d.axis == Axis.x);
      if (onMirroredAxis) {
        final rotated = rotateState(s, BlockRotation.clockwise180);
        return rotated.setValue('shape', switch (shape) {
          'inner_left' => 'inner_right',
          'inner_right' => 'inner_left',
          'outer_left' => 'outer_right',
          'outer_right' => 'outer_left',
          _ => shape,
        });
      }
      return s;
    }
  }

  var out = s;
  // Facing blocks turn around when they look along the mirrored axis.
  if (facing != null && !_noFacingRotation(s)) {
    final d = Direction.byName(facing);
    if (d != null) {
      final r = m.getRotation(d);
      if (r != BlockRotation.none) out = rotateState(out, r);
    }
  }

  // Doors swap their hinge.
  if (s.has('hinge')) {
    out = out.setValue('hinge', s['hinge'] == 'left' ? 'right' : 'left');
  }

  final rotation = s['rotation'];
  if (rotation != null) {
    final v = int.tryParse(rotation);
    if (v != null && v >= 0 && v < 16) out = out.setValue('rotation', '${m.mirrorInt(v, 16)}');
  }

  if (_sides.every(s.has)) {
    final props = {...out.props};
    if (m == BlockMirror.leftRight) {
      props['north'] = s['south']!;
      props['south'] = s['north']!;
    } else {
      props['east'] = s['west']!;
      props['west'] = s['east']!;
    }
    out = BState(out.key, props);
  }

  if (shape != null && _railShapes.contains(shape)) {
    out = out.setValue('shape', _mirrorRail(shape, m));
  }

  final orientation = s['orientation'];
  if (orientation != null) {
    final o = _parseOrientation(orientation);
    if (o != null) {
      final r = m.getRotation(o.$2);
      if (r != BlockRotation.none) out = rotateState(out, r);
    }
  }
  return out;
}

/// Blocks whose `facing` is not a direction they turn with (none among the ones we know; the hook
/// exists for blocks added later).
bool _noFacingRotation(BState s) => false;

// ---- rails -----------------------------------------------------------------------------------

const Set<String> _railShapes = {
  'north_south', 'east_west', 'ascending_east', 'ascending_west', 'ascending_north', 'ascending_south',
  'south_east', 'south_west', 'north_west', 'north_east',
};

const Set<String> _stairShapes = {'straight', 'inner_left', 'inner_right', 'outer_left', 'outer_right'};

String _rotateRail(String shape, BlockRotation r) {
  switch (r) {
    case BlockRotation.clockwise180:
      return switch (shape) {
        'ascending_east' => 'ascending_west',
        'ascending_west' => 'ascending_east',
        'ascending_north' => 'ascending_south',
        'ascending_south' => 'ascending_north',
        'south_east' => 'north_west',
        'south_west' => 'north_east',
        'north_west' => 'south_east',
        'north_east' => 'south_west',
        _ => shape,
      };
    case BlockRotation.counterclockwise90:
      return switch (shape) {
        'north_south' => 'east_west',
        'east_west' => 'north_south',
        'ascending_east' => 'ascending_north',
        'ascending_west' => 'ascending_south',
        'ascending_north' => 'ascending_west',
        'ascending_south' => 'ascending_east',
        'south_east' => 'north_east',
        'south_west' => 'south_east',
        'north_west' => 'south_west',
        'north_east' => 'north_west',
        _ => shape,
      };
    case BlockRotation.clockwise90:
      return switch (shape) {
        'north_south' => 'east_west',
        'east_west' => 'north_south',
        'ascending_east' => 'ascending_south',
        'ascending_west' => 'ascending_north',
        'ascending_north' => 'ascending_east',
        'ascending_south' => 'ascending_west',
        'south_east' => 'south_west',
        'south_west' => 'north_west',
        'north_west' => 'north_east',
        'north_east' => 'south_east',
        _ => shape,
      };
    case BlockRotation.none:
      return shape;
  }
}

String _mirrorRail(String shape, BlockMirror m) {
  switch (m) {
    case BlockMirror.leftRight:
      return switch (shape) {
        'ascending_north' => 'ascending_south',
        'ascending_south' => 'ascending_north',
        'south_east' => 'north_east',
        'south_west' => 'north_west',
        'north_west' => 'south_west',
        'north_east' => 'south_east',
        _ => shape,
      };
    case BlockMirror.frontBack:
      return switch (shape) {
        'ascending_east' => 'ascending_west',
        'ascending_west' => 'ascending_east',
        'south_east' => 'south_west',
        'south_west' => 'south_east',
        'north_west' => 'north_east',
        'north_east' => 'north_west',
        _ => shape,
      };
    case BlockMirror.none:
      return shape;
  }
}

// ---- crafter orientation -----------------------------------------------------------------------

/// `down_east` -> (down, east): the front and the top of a `FrontAndTop`.
(Direction, Direction)? _parseOrientation(String s) {
  const names = ['down', 'up', 'north', 'south', 'west', 'east'];
  for (final front in names) {
    if (s.startsWith('${front}_')) {
      final top = s.substring(front.length + 1);
      final f = Direction.byName(front), t = Direction.byName(top);
      if (f != null && t != null) return (f, t);
    }
  }
  return null;
}
