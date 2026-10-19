// `FakeTrackBlock` and `FakeTrackBlockEntity` (pure): the invisible blocks along a curved track
// that keep the curve free. They expire unless the curve's block entity keeps them alive.
import '../../api/block_state.dart';
import '../../common/common.dart';
import 'track_level.dart';

/// `create:fake_track`.
const String fakeTrackKey = 'create:fake_track';

/// `AllBlocks.FAKE_TRACK.getDefaultState()`.
const BState fakeTrackDefaultState = BState(fakeTrackKey, {'waterlogged': 'false'});

/// `FakeTrackBlockEntity`.
class FakeTrackBlockEntity {
  final Pos worldPosition;
  int keepAliveCounter = 0;

  /// Called by [randomTick] to remove the block (`level.removeBlock(worldPosition, false)`).
  final Future<void> Function(Pos pos) removeBlock;

  FakeTrackBlockEntity(this.worldPosition, this.removeBlock) {
    keepAlive();
  }

  /// `randomTick()`.
  Future<void> randomTick() async {
    keepAliveCounter--;
    if (keepAliveCounter > 0) return;
    await removeBlock(worldPosition);
  }

  /// `keepAlive()`.
  void keepAlive() {
    keepAliveCounter = 3;
  }
}

/// `FakeTrackBlock`.
abstract final class FakeTrackBlock {
  /// `keepAlive(level, pos)`.
  static void keepAlive(TrackLevel level, Pos pos) {
    level.getFakeTrackBlockEntity(pos)?.keepAlive();
  }

  /// `randomTick(state, level, pos, random)`.
  static Future<void> randomTick(TrackLevel level, Pos pos) async {
    final be = level.getFakeTrackBlockEntity(pos);
    if (be != null) await be.randomTick();
  }
}
