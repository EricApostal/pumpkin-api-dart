// The arithmetic of a `TrackTargetingBehaviour` target, kept free of the host API so tests can
// run on the VM (the block entity and the item are wasm-only).
//
// A station, signal or observer stores its target as `TargetTrack`, the selected track position
// relative to the block entity (`TrackTargetingBlockItem.useOn`: `selectedPos.subtract(placedPos)`
// -> `TrackTargetingBlockEntity.read` -> [resolvedTarget]).
import '../../common/pos.dart' hide pos;

/// `TargetTrack` of a placement: the track position [selectedPos], relative to [placedPos].
Pos targetOffset(Pos placedPos, Pos selectedPos) => selectedPos - placedPos;

/// `TrackTargetingBehaviour.getGlobalPosition()`: the absolute track position, from the block
/// entity position [placedPos] and its [offset].
///
/// Without a written target the offset is `posZero`, so the target is the block's own position -
/// which is never a track, and `hasValidTrack()` stays false.
Pos resolvedTarget(Pos placedPos, Pos offset) => offset + placedPos;
