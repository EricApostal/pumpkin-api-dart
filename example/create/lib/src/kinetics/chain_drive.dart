// The shape logic of the encased chain drive and the adjustable chain gearshift
// (`ChainDriveBlock`), pure: which neighbours a chain drive links to.
import 'geometry.dart';
import 'node.dart';

KAxis _connectionAxisOf(KAxis axis, bool alongFirst) =>
    alongFirst ? (axis == KAxis.x ? KAxis.y : KAxis.x) : (axis == KAxis.z ? KAxis.y : KAxis.z);

/// `ChainDriveBlock.updateShape`: the new state of [stateIn] when the
/// neighbour on the side [face] changed to [neighbour].
KState chainDriveUpdateShape(KState stateIn, Dir face, KState neighbour, KineticBlockRegistry blocks) {
  var part = stateIn['part'] ?? 'none';
  final axis = stateIn.axisOf('axis') ?? KAxis.y;
  var connectionAlongFirst = stateIn.flag('axis_along_first');
  final connectionAxis = _connectionAxisOf(axis, connectionAlongFirst);

  final faceAxis = face.axis;
  final facingAlongFirst = axis == KAxis.x ? faceAxis.isVertical : faceAxis == KAxis.x;
  final positive = face.isPositive;

  if (axis == faceAxis) return stateIn;

  if (!blocks.isChainDrive(neighbour)) {
    if (facingAlongFirst != connectionAlongFirst || part == 'none') return stateIn;
    if (part == 'middle') return stateIn.set('part', positive ? 'end' : 'start');
    if ((part == 'start') == positive) return stateIn.set('part', 'none');
    return stateIn;
  }

  final otherPart = neighbour['part'] ?? 'none';
  final otherAxis = neighbour.axisOf('axis') ?? KAxis.y;
  final otherConnection = neighbour.flag('axis_along_first');
  final otherConnectionAxis = _connectionAxisOf(otherAxis, otherConnection);

  if (neighbour.axisOf('axis') == faceAxis) return stateIn;
  if (otherPart != 'none' && otherConnectionAxis != faceAxis) return stateIn;

  if (part == 'none') {
    part = positive ? 'start' : 'end';
    connectionAlongFirst = axis == KAxis.x ? faceAxis.isVertical : faceAxis == KAxis.x;
  } else if (connectionAxis != faceAxis) {
    return stateIn;
  }

  if ((part == 'start') != positive) part = 'middle';

  return stateIn.setAll({'part': part, 'axis_along_first': '$connectionAlongFirst'});
}

/// Applies [chainDriveUpdateShape] for every side but the axis (what
/// `getStateForPlacement` and `updateAfterWrenched` do).
KState chainDriveSettle(KState state, KPos pos, KState Function(KPos pos) stateAt, KineticBlockRegistry blocks) {
  final axis = state.axisOf('axis') ?? KAxis.y;
  var s = state;
  for (final facing in Dir.values) {
    if (facing.axis == axis) continue;
    s = chainDriveUpdateShape(s, facing, stateAt(pos.relative(facing)), blocks);
  }
  return s;
}

/// `ChainDriveBlock.getConnectionAxis`.
KAxis chainConnectionAxis(KState state) =>
    _connectionAxisOf(state.axisOf('axis') ?? KAxis.y, state.flag('axis_along_first'));
