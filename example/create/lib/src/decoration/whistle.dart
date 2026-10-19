// Steam whistles (pure): `WhistleBlock`, `WhistleExtenderBlock` and the pitch of
// `WhistleBlockEntity.updatePitch`.
import 'dart:math' as math;

import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';

const String whistleKey = 'create:steam_whistle';
const String whistleExtensionKey = 'create:steam_whistle_extension';
const List<String> whistleSizes = ['small', 'medium', 'large'];

/// `FluidTankBlock.isTank`.
bool isFluidTank(BState s) => s.key == 'create:fluid_tank' || s.key == 'create:creative_fluid_tank';

/// `WhistleBlock.getAttachedDirection`.
Direction whistleAttachedDirection(BState state) =>
    state.flag('wall') ? state.dir('facing')! : Direction.down;

/// `WhistleBlock.canSurvive`: the whistle sits on a fluid tank.
bool whistleCanSurvive(BlockGetter level, Pos pos, BState state) =>
    isFluidTank(level.stateAt(pos.relative(whistleAttachedDirection(state))));

/// `WhistleBlock.getStateForPlacement`; `null` when no tank is behind. [defaultState] is the block's
/// default state; [horizontalDirection] the placer's horizontal direction.
BState? whistleStateForPlacement({
  required BlockGetter level,
  required Pos pos,
  required BState defaultState,
  required Direction clickedFace,
  required Direction horizontalDirection,
  required bool hasNeighborSignal,
}) {
  var face = clickedFace;
  var wall = true;
  if (face.axis == Axis.y) {
    face = horizontalDirection.opposite;
    wall = false;
  }
  final state = defaultState
      .setValue('facing', face.opposite.serializedName)
      .setFlag('powered', hasNeighborSignal)
      .setFlag('wall', wall);
  return whistleCanSurvive(level, pos, state) ? state : null;
}

/// `WhistleBlock.updateShape`: the whistle disappears when its tank goes.
BState whistleUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) =>
    whistleAttachedDirection(state) == direction && !whistleCanSurvive(level, pos, state) ? BState.air : state;

/// `WhistleExtenderBlock.canSurvive`.
bool whistleExtenderCanSurvive(BlockGetter level, Pos pos, BState state) {
  final below = level.stateAt(pos.below);
  return (below.key == state.key && below['shape'] != 'single') || below.key == whistleKey;
}

/// `WhistleExtenderBlock.updateShape`.
BState whistleExtenderUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) {
  if (direction.axis != Axis.y) return state;
  if (direction == Direction.up) {
    final connected = state['shape'] == 'double_connected';
    final shouldConnect = level.stateAt(pos.above).key == state.key;
    if (!connected && shouldConnect) return state.setValue('shape', 'double_connected');
    if (connected && !shouldConnect) return state.setValue('shape', 'double');
    return state;
  }
  if (!whistleExtenderCanSurvive(level, pos, state)) return BState.air;
  final below = level.stateAt(pos.below);
  final size = below['size'];
  return size == null ? state : state.setValue('size', size);
}

/// `WhistleExtenderBlock.findRoot`: the position of the whistle (or the first non-extension block)
/// below an extension.
Pos whistleFindRoot(BlockGetter level, Pos pos) {
  var current = pos.below;
  while (true) {
    final s = level.stateAt(current);
    if (s.key == whistleExtensionKey) {
      current = current.below;
      continue;
    }
    return current;
  }
}

/// `WhistleBlockEntity.updatePitch`: the pitch in semitones from the extension stack above [pos].
int whistlePitchAt(BlockGetter level, Pos pos) {
  var current = pos.above;
  int newPitch;
  for (newPitch = 0; newPitch <= 24; newPitch += 2) {
    final s = level.stateAt(current);
    if (s.key != whistleExtensionKey) break;
    if (s['shape'] == 'single') {
      newPitch++;
      break;
    }
    current = current.above;
  }
  return newPitch;
}

/// `WhistleBlockEntity.getPitchId`.
int whistlePitchId(int pitch, String size) {
  final i = whistleSizes.indexOf(size);
  return pitch + 100 * (i < 0 ? 1 : i);
}

/// What `WhistleBlock.incrementSize` does: a block change and the sound to play (the pitch is
/// `2^(-semitones / 12)` for both the grow note and the hit sound).
final class WhistleGrowth {
  final Pos pos;
  final BState state;
  final double pitch;

  const WhistleGrowth(this.pos, this.state, this.pitch);
}

/// `WhistleBlock.incrementSize`: adds one extension on the stack above the whistle at [pos] (or
/// extends the top single one to a double). Returns `null` when nothing can be added.
WhistleGrowth? whistleIncrementSize(BlockGetter level, Pos pos, BState extensionDefault) {
  final base = level.stateAt(pos);
  if (!base.has('size')) return null;
  final size = base['size']!;
  var current = pos.above;
  for (var i = 1; i <= 6; i++) {
    final s = level.stateAt(current);
    if (s.key == whistleExtensionKey) {
      if (s['shape'] == 'single') {
        final pitch = _pow2(-(i * 2) / 12.0);
        return WhistleGrowth(current, s.setValue('shape', 'double'), pitch);
      }
      current = current.above;
      continue;
    }
    if (!level.canBeReplaced(current)) return null;
    final pitch = _pow2(-(i * 2 - 1) / 12.0);
    return WhistleGrowth(current, extensionDefault.setValue('size', size), pitch);
  }
  return null;
}

double _pow2(double e) => math.pow(2, e).toDouble();
