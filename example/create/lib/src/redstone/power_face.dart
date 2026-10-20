// The redstone power event's side convention (pure): the host hands a custom block the face
// that touches the block asking for power, while vanilla `getSignal`/`getDirectSignal` receive
// the side of the block asking. The two are opposite.
//
// `dynamic.rs` (`redstone_power`): `let face = args.direction.opposite();` — `args.direction`
// points from the reader to the block, and that same `face` goes to the plugin event.
import '../common/direction.dart';

/// Vanilla's `side` of a `CustomBlockRedstonePowerEvent`: the side of the block asking for the
/// power, opposite the [face] of the custom block that touches it.
Direction powerEventSide(Direction face) => face.opposite;
