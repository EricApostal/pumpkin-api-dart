// Rotating and mirroring the kinetic states whose rotation needs more than the
// plain `facing` / `axis` conventions (`rotate` / `mirror` of the Java blocks):
// encased cogwheels (shaft stubs), chain drives (connection side) and gauges
// (`axis_along_first`). Everything else follows the generic rules of the
// schematics module. Pure.
import 'geometry.dart';
import 'node.dart';

/// The result for blocks this module knows, `null` for all others (use the generic rule).
/// [clockwiseTurns] is `Rotation.ordinal()`: 0 none, 1 clockwise 90, 2 clockwise 180, 3 counterclockwise 90.
KState? rotateKineticState(KState state, int clockwiseTurns, KineticBlockRegistry blocks) {
  final t = clockwiseTurns & 3;
  final path = state.path;
  if (path.endsWith('encased_cogwheel') || path.endsWith('encased_large_cogwheel')) {
    var s = state;
    if (t != 0) {
      final axis = state.axisOf('axis') ?? KAxis.y;
      if (axis != KAxis.y) {
        if (t == 2) {
          s = _swapShafts(s);
        } else {
          final clockwise = t == 1;
          if ((axis == KAxis.x && !clockwise) || (axis == KAxis.z && clockwise)) s = _swapShafts(s);
        }
      }
    }
    return _rotatePillar(s, t);
  }
  if (blocks.isChainDrive(state)) return _rotateChain(state, t, KAxis.y);
  if (path == 'speedometer' || path == 'stressometer') {
    var s = state;
    if (t.isOdd) s = s.toggle('axis_along_first');
    final facing = s.dirOf('facing');
    if (facing != null) {
      var f = facing;
      for (var i = 0; i < t; i++) {
        f = f.clockWise(KAxis.y);
      }
      s = s.set('facing', f.name);
    }
    return s;
  }
  return null;
}

/// `Mirror`: [frontBack] mirrors the x axis, [leftRight] the z axis.
KState? mirrorKineticState(KState state, {required bool frontBack, required bool leftRight}) {
  final path = state.path;
  if (path.endsWith('encased_cogwheel') || path.endsWith('encased_large_cogwheel')) {
    final axis = state.axisOf('axis') ?? KAxis.y;
    if ((axis == KAxis.x && frontBack) || (axis == KAxis.z && leftRight)) return _swapShafts(state);
    return state;
  }
  if (path.endsWith('chain_drive') || path == 'adjustable_chain_gearshift') {
    final connection = _connectionAxis(state);
    final mirrored = (connection == KAxis.x && frontBack) || (connection == KAxis.z && leftRight);
    return mirrored ? _reversePart(state) : state;
  }
  return null;
}

KState _swapShafts(KState s) {
  final bottom = s['bottom_shaft'] ?? 'false';
  final top = s['top_shaft'] ?? 'false';
  return s.setAll({'bottom_shaft': top, 'top_shaft': bottom});
}

KState _rotatePillar(KState s, int turns) {
  if (turns == 0) return s;
  final axis = s.axisOf('axis');
  if (axis == null || axis == KAxis.y || turns == 2) return s;
  return s.set('axis', (axis == KAxis.x ? KAxis.z : KAxis.x).name);
}

KAxis _connectionAxis(KState state) {
  final axis = state.axisOf('axis') ?? KAxis.y;
  final alongFirst = state.flag('axis_along_first');
  return alongFirst ? (axis == KAxis.x ? KAxis.y : KAxis.x) : (axis == KAxis.z ? KAxis.y : KAxis.z);
}

KState _reversePart(KState s) => switch (s['part']) {
  'start' => s.set('part', 'end'),
  'end' => s.set('part', 'start'),
  _ => s,
};

/// `ChainDriveBlock.rotate(state, rot, rotAxis)`.
KState _rotateChain(KState state, int turns, KAxis rotAxis) {
  final connectionAxis = _connectionAxis(state);
  var direction = connectionAxis.positive;
  var normal = (state.axisOf('axis') ?? KAxis.y).positive;
  for (var i = 0; i < turns; i++) {
    direction = direction.clockWise(rotAxis);
    normal = normal.clockWise(rotAxis);
  }

  var s = state;
  if (!direction.isPositive) s = _reversePart(s);

  final newAxis = normal.axis;
  final newConnecting = direction.axis;
  final alongFirst = (newAxis == KAxis.x && newConnecting == KAxis.y) || (newAxis != KAxis.x && newConnecting == KAxis.x);
  return s.setAll({'axis': newAxis.name, 'axis_along_first': '$alongFirst'});
}
