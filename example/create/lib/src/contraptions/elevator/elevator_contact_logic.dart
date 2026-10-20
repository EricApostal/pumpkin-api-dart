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

/// `ElevatorContactBlock.getSignal` (the weak power of the contact at [pos]).
///
/// [side] is the side of the contact the power is read from, as the event gives it: the side
/// *away* from the reader (Java's `side.getOpposite()`, the host's `face`). A contact directly
/// there does not power it; otherwise the contact powers while its `powering` state is set.
int elevatorContactWeakPower(BlockGetter level, Pos pos, Direction side) {
  final state = level.stateAt(pos);
  if (level.stateAt(pos.relative(side)).key == elevatorContactKey) return 0;
  return state.flag('powering') ? 15 : 0;
}

/// Whether redstone wire connects to [side] of the contact at [pos]: the host connects wire to
/// every side of a signal source by default, and vanilla does not connect it on the side the
/// contact faces (the side the elevator sits on).
///
/// The `facing` comes from the state at [pos], like Java's `canConnectRedstone(state, ...)`.
bool elevatorContactCanConnect(BlockGetter level, Pos pos, Direction? side) {
  final facing = level.stateAt(pos).dir('facing') ?? Direction.south;
  return side == null || side != facing.opposite;
}
