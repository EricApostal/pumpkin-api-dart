// The decisions of a bulk track write (pure, so they run on the plain Dart VM in tests): which
// blocks the host still has to write, and which of them need the plugin's own `placed` handling
// afterwards. `HostTrackLevel.setBlocks` (`track_host.dart`) is the host half.
//
// Why the plugin fires `placed` itself: the host fires it for every block it writes, one
// host-to-plugin round trip per block. Measured on a live server, one such callback costs tens of
// milliseconds (the write of the block itself is microseconds and the handler body ~0.06ms),
// which is the tick a placement used to spike. `setBlocks` writes the batch with
// `BlockFlagsFlag.skipBlockAddedCallback` - one host call for the whole run - and then runs the
// same handling from this plan.
import '../../api/block_state.dart';
import '../../common/pos.dart';
import '../../core/state_layouts.dart';

/// One block a placement wants written: its position and the state it should have.
typedef TrackChange = (Pos pos, BState state);

/// One block a bulk write actually wrote: the state it got, its state id and the state id that
/// was at the position before (so the plugin's `placed` handling sees what the host would give it).
typedef TrackWrite = (Pos pos, BState state, int stateId, int oldStateId);

/// The `placed` event of one written block: its position, its block key, the `stateIndex` of the
/// state within the block and the state id that was there before.
typedef PlacedBlock = (Pos pos, String blockKey, int stateIndex, int oldStateId);

/// The blocks of [changes] the host still has to write, in order.
///
/// A block that already has the state is skipped, the way `Level.setBlock` returns without
/// touching the block entity when the state does not change - a track written over itself keeps
/// its block entity. [currentStateAt] reads the state id at a position and [idOf] the state id of
/// a state (both host calls in game).
List<TrackWrite> planTrackWrite(
  List<TrackChange> changes, {
  required int Function(Pos pos) currentStateAt,
  required int? Function(BState state) idOf,
}) {
  final writes = <TrackWrite>[];
  for (final (pos, state) in changes) {
    final stateId = idOf(state);
    if (stateId == null) continue;
    final oldStateId = currentStateAt(pos);
    if (oldStateId == stateId) continue;
    writes.add((pos, state, stateId, oldStateId));
  }
  return writes;
}

/// The `placed` handling `HostTrackLevel` has to run itself for [writes]: one entry per write, in
/// the same order, `null` for a block this plugin registered no behavior for (there is no
/// `stateIndex` to report for a block whose states this plugin does not number).
///
/// `stateIndex` is the index of the state within its block (`state id = baseStateId +
/// stateIndex`, `docs/block-callbacks.md`), which is what the host's event carries.
List<PlacedBlock?> planPlacedHandling(List<TrackWrite> writes) {
  final plan = <PlacedBlock?>[];
  for (final (pos, state, stateId, oldStateId) in writes) {
    final range = PluginStateLayouts.byKey(state.key);
    plan.add(
      range == null ? null : (pos, state.key, stateId - range.base, oldStateId),
    );
  }
  return plan;
}