// The redstone rules of `ElevatorContactBlock`, pure so `dart test` covers them: the weak power
// the contact emits and whether redstone wire connects to a side.
//
// The state these read is the state at the position (`getSignal(state, ...)` and
// `canConnectRedstone(state, ...)` in Java). It must not come from a block callback's
// `stateIndex`: that counts the states of the block, so `state id = baseStateId + stateIndex`
// (`docs/block-callbacks.md`), and the index of a contact resolves to a vanilla state whose
// missing `facing`/`powering` fall back to south/false.
//
// Java: `content/contraptions/elevator/ElevatorContactBlock`.
import '../../api/block_state.dart';
import '../../common/common.dart';

const String elevatorContactKey = 'create:elevator_contact';

/// `ElevatorContactBlock.getSignal` (the weak power of the contact at [pos]): a contact directly
/// behind the reading [side] does not power it, else the contact powers while it is `powering`.
int elevatorContactWeakPower(BlockGetter level, Pos pos, Direction side) {
  final state = level.stateAt(pos);
  if (level.stateAt(pos.relative(side)).key == elevatorContactKey) return 0;
  return state.flag('powering') ? 15 : 0;
}

/// `ElevatorContactBlock.canConnectRedstone`: redstone wire does not connect on the side the
/// contact faces.
bool elevatorContactCanConnect(BlockGetter level, Pos pos, Direction? side) {
  final facing = level.stateAt(pos).dir('facing') ?? Direction.south;
  return side == null || side != facing.opposite;
}
