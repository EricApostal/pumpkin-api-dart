// Rotating and mirroring block states (pure): what `BlockState.rotate(Rotation)` and
// `BlockState.mirror(Mirror)` do for vanilla blocks and for Create's blocks that follow the same
// property conventions (`facing`, `axis`, `rotation`, `north/east/south/west`, rail `shape`, stair
// `shape`, door `hinge`, crafter `orientation`). `StructureTemplate` placement mirrors first and
// then rotates ([transformState]).
//
// Create's own overrides are ported too: `DirectionalAxisKineticBlock`/`BracketBlock`
// (`axis_along_first` cycles on a quarter turn), `BeltBlock` (a vertical belt swaps start/end when
// its facing turns) and `TrackBlock` (`TrackShape`).
import '../api/block_state.dart';
import '../common/direction.dart';

const List<String> _sides = ['north', 'east', 'south', 'west'];

/// The state after `mirror` and then `rotation`, the order of `StructureTemplate.placeInWorld`.
BState transformState(
  BState state,
  BlockMirror mirror,
  BlockRotation rotation,
) => rotateState(mirrorState(state, mirror), rotation);

/// `BlockState.rotate(Rotation)`.
BState rotateState(BState s, BlockRotation r) {
  if (r == BlockRotation.none || s.props.isEmpty) return s;
  var props = s.props;
  Map<String, String> changed = {};

  // facing (6 directions or horizontal)
  final facing = s['facing'];
  final facingDir = facing == null ? null : Direction.byName(facing);
  if (facingDir != null) {
    changed['facing'] = r.rotate(facingDir).serializedName;
  }

  // axis: only the horizontal axes swap on a quarter turn
  final axis = s['axis'];
  if (axis != null &&
      (r == BlockRotation.clockwise90 ||
          r == BlockRotation.counterclockwise90)) {
    if (axis == 'x') changed['axis'] = 'z';
    if (axis == 'z') changed['axis'] = 'x';
  }

  // rotation 0..15
  final rotation = s['rotation'];
  if (rotation != null) {
    final v = int.tryParse(rotation);
    if (v != null && v >= 0 && v < 16)
      changed['rotation'] = '${r.rotateInt(v, 16)}';
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
  if (shape != null) {
    if (_railShapes.contains(shape)) {
      changed['shape'] = _rotateRail(shape, r);
    } else if (_isTrack(s)) {
      changed['shape'] = _rotateTrackShape(shape, r);
    }
  }

  // crafter / jigsaw orientation
  final orientation = s['orientation'];
  if (orientation != null) {
    final o = _parseOrientation(orientation);
    if (o != null)
      changed['orientation'] =
          '${r.rotate(o.$1).serializedName}_${r.rotate(o.$2).serializedName}';
  }

  // Create: `DirectionalAxisKineticBlock.rotate` / `BracketBlock.rotate` cycle
  // `axis_along_first` on every odd quarter turn (deployer, piston, gantry carriage, bracket,
  // valve, chain drive).
  final alongFirst = s['axis_along_first'];
  if (alongFirst != null &&
      (r == BlockRotation.clockwise90 ||
          r == BlockRotation.counterclockwise90)) {
    changed['axis_along_first'] = alongFirst == 'true' ? 'false' : 'true';
  }

  // Create: `BeltBlock.rotate` swaps the ends of a vertical belt when its facing turns.
  if (s.key == 'create:belt' &&
      s['slope'] == 'vertical' &&
      facingDir != null &&
      facingDir.axisDirection != r.rotate(facingDir).axisDirection) {
    final part = s['part'];
    if (part == 'start') changed['part'] = 'end';
    if (part == 'end') changed['part'] = 'start';
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

  // Stairs mirror their corner shapes (`StairBlock.mirror`): `LEFT_RIGHT` turns both inner and
  // outer corners into their opposite, `FRONT_BACK` only the outer ones (the inner shapes are
  // symmetric along X).
  if (facing != null &&
      shape != null &&
      _stairShapes.contains(shape) &&
      s.has('half')) {
    final d = Direction.byName(facing);
    if (d != null) {
      final onMirroredAxis =
          (m == BlockMirror.leftRight && d.axis == Axis.z) ||
          (m == BlockMirror.frontBack && d.axis == Axis.x);
      if (onMirroredAxis) {
        final rotated = rotateState(s, BlockRotation.clockwise180);
        return rotated.setValue('shape', _mirrorStairShape(shape, m));
      }
      return s;
    }
  }

  var out = s;
  // Facing blocks turn around when they look along the mirrored axis.
  if (facing != null) {
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
    if (v != null && v >= 0 && v < 16)
      out = out.setValue('rotation', '${m.mirrorInt(v, 16)}');
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

  if (shape != null) {
    if (_railShapes.contains(shape)) {
      out = out.setValue('shape', _mirrorRail(shape, m));
    } else if (_isTrack(s)) {
      out = out.setValue('shape', _mirrorTrackShape(shape, m));
    }
  }

  // `ChestBlock.mirror` keeps a double chest together by swapping its left and right halves.
  final type = s['type'];
  if (type == 'left') {
    out = out.setValue('type', 'right');
  } else if (type == 'right') {
    out = out.setValue('type', 'left');
  }

  // `FrontAndTop` mirroring (`OctahedralGroup`): both the front and the top are mirrored, which
  // is not the same as rotating by the top's axis (the top is often vertical).
  final orientation = s['orientation'];
  if (orientation != null) {
    final o = _parseOrientation(orientation);
    if (o != null) {
      out = out.setValue(
        'orientation',
        '${m.mirrorDirection(o.$1).serializedName}_${m.mirrorDirection(o.$2).serializedName}',
      );
    }
  }
  return out;
}

/// The stair shape after [m] (`StairBlock.mirror`).
String _mirrorStairShape(String shape, BlockMirror m) => m == BlockMirror.leftRight
    ? switch (shape) {
        'inner_left' => 'inner_right',
        'inner_right' => 'inner_left',
        'outer_left' => 'outer_right',
        'outer_right' => 'outer_left',
        _ => shape,
      }
    : switch (shape) {
        'outer_left' => 'outer_right',
        'outer_right' => 'outer_left',
        _ => shape,
      };

// ---- Create tracks ------------------------------------------------------------------------------

/// `TrackBlock` uses its own `TrackShape` (`TrackShape.getSerializedName()` lowercases the
/// constant name: `zo`, `xo`, `pd`, `nd`, `an`, `as`, `ae`, `aw`, `tn`, ..., `cr_pdx`, ...).
bool _isTrack(BState s) => s.key == 'create:track';

/// `TrackShape.clockwise`: one clockwise quarter turn.
const Map<String, String> _clockwiseTrack = {
  'pd': 'nd',
  'nd': 'pd',
  'xo': 'zo',
  'zo': 'xo',
  'ae': 'as',
  'as': 'aw',
  'aw': 'an',
  'an': 'ae',
  'cr_pdx': 'cr_ndz',
  'cr_ndx': 'cr_pdz',
  'cr_pdz': 'cr_ndx',
  'cr_ndz': 'cr_pdx',
};

/// `TrackShape.mirror` for `LEFT_RIGHT` (invert Z).
const Map<String, String> _zMirrorTrack = {
  'pd': 'nd',
  'nd': 'pd',
  'an': 'as',
  'as': 'an',
  'cr_pdx': 'cr_ndx',
  'cr_ndx': 'cr_pdx',
  'cr_pdz': 'cr_ndz',
  'cr_ndz': 'cr_pdz',
};

/// `TrackShape.mirror` for `FRONT_BACK` (invert X).
const Map<String, String> _xMirrorTrack = {
  'pd': 'nd',
  'nd': 'pd',
  'ae': 'aw',
  'aw': 'ae',
  'cr_pdx': 'cr_ndx',
  'cr_ndx': 'cr_pdx',
  'cr_pdz': 'cr_ndz',
  'cr_ndz': 'cr_pdz',
};

String _rotateTrackShape(String shape, BlockRotation r) {
  var out = shape;
  for (var i = 0; i < r.index; i++) {
    out = _clockwiseTrack[out] ?? out;
  }
  return out;
}

String _mirrorTrackShape(String shape, BlockMirror m) =>
    (m == BlockMirror.leftRight ? _zMirrorTrack : _xMirrorTrack)[shape] ?? shape;

// ---- rails -----------------------------------------------------------------------------------

const Set<String> _railShapes = {
  'north_south',
  'east_west',
  'ascending_east',
  'ascending_west',
  'ascending_north',
  'ascending_south',
  'south_east',
  'south_west',
  'north_west',
  'north_east',
};

const Set<String> _stairShapes = {
  'straight',
  'inner_left',
  'inner_right',
  'outer_left',
  'outer_right',
};

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
