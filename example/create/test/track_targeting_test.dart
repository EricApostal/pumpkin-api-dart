// The target arithmetic of a placed station, signal or observer: a placement stores the selected
// track position *relative* to the block entity (`TargetTrack`) and the behaviour resolves it back
// to an absolute position. This is the regression that "right-clicking a station onto a track does
// nothing" hid: when nothing writes `TargetTrack`, the offset stays `posZero`, so the target
// resolves to the block's **own** position - never the track the player picked - and
// `hasValidTrack()` is false forever, `createEdgePoint()` returns null every tick, and the station
// / signal / observer is dead. Both call sites share `track/track_targeting_data.dart`
// (`_onTargetingBlockPlaced` writes `targetOffset`, `TrackTargetingBehaviour.getGlobalPosition`
// reads `resolvedTarget`), so this fails if either side drifts.
//
// Java sources (branch `port/26.3`):
//   content/trains/track/TrackTargetingBlockItem.java:150-163   useOn: TargetTrack = selectedPos - placedPos
//   content/trains/track/TrackTargetingBehaviour.java           getGlobalPosition(): targetTrack + pos
//
// The host half (the item hook, the block entity) is wasm-only and cannot be imported by a VM
// test; this covers the arithmetic both halves go through.
import 'package:create/src/common/pos.dart';
import 'package:create/src/trains/track/track_targeting_data.dart';
import 'package:test/test.dart';

void main() {
  group('track target arithmetic', () {
    test('a station placed beside the rail resolves to the picked track position', () {
      // The station block sits next to the track, four blocks along it.
      const placedPos = (4, 62, -7);
      const selectedPos = (4, 62, -3);

      expect(targetOffset(placedPos, selectedPos), (0, 0, 4));
      expect(resolvedTarget(placedPos, targetOffset(placedPos, selectedPos)), selectedPos);
    });

    test('offsets are signed on every axis', () {
      const placedPos = (0, 64, 0);
      const selected = [
        (3, 64, 0), // behind the block
        (-2, 64, 1), // the other way along the rail
        (0, 63, -5), // the rail drops below the block
        (1, 66, 2), // and rises above it
        posZero, // a block placed on the track itself
      ];

      for (final pos in selected) {
        expect(
          resolvedTarget(placedPos, targetOffset(placedPos, pos)),
          pos,
          reason: 'the target of $pos must survive the relative form',
        );
      }
    });

    test('without a written target the target is the block position, not the track', () {
      const placedPos = (4, 62, -7);
      const selectedPos = (4, 62, -3);

      // `TrackTargetingBehaviour.read` falls back to `posZero` when the placement carried no
      // `TargetTrack` - the state the missing `useOn` left every placement in.
      final unset = resolvedTarget(placedPos, posZero);
      expect(unset, placedPos);
      expect(unset, isNot(selectedPos));
    });
  });
}