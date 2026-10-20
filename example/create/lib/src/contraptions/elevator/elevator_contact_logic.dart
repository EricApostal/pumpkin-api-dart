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
/// [side] is the event's `face`: the side of the contact that faces the reader. A contact on that
/// side does not power it; otherwise the contact powers while its `powering` state is set.
///
/// (Java checks `side.getOpposite()`, the side away from the reader. That difference predates this
/// helper and is kept: the state source is what was wrong here, not the neighbour rule.)
int elevatorContactWeakPower(BlockGetter level, Pos pos, Direction side) {
  final state = level.stateAt(pos);
  if (level.stateAt(pos.relative(side)).key == elevatorContactKey) return 0;
  return state.flag('powering') ? 15 : 0;
}

/// Whether redstone wire connects to [side] of the contact at [pos]: the port's rule is that it
/// does not connect on the side opposite the contact's `facing`, and connects everywhere else
/// (`null` side: any side).
///
/// The `facing` comes from the state at [pos]. Reading a vanilla state instead (a per-block
/// `stateIndex` used as a state id) leaves `facing` missing, so the fallback refused the wrong
/// side.
bool elevatorContactCanConnect(BlockGetter level, Pos pos, Direction? side) {
  final facing = level.stateAt(pos).dir('facing') ?? Direction.south;
  return side == null || side != facing.opposite;
}
