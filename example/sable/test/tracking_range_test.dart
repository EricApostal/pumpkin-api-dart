// Tracking range: who is tracking a sub-level, and when that changes.
//
// `shouldLoad` is a *strict* sphere test against `sub_level_tracking_range`:
// a player exactly `range` blocks away is **not** tracking. The add path runs
// in `onSubLevelAdded` (a full sync immediately) and in `tick` (a full sync
// when a player walks into range); the drop path runs in `tick` and sends one
// `stop_tracking_sub_level` per player that left.
//
// Transcribed from `SubLevelTrackingSystem.shouldLoad` / `updateTrackingPlayers`
// on `port/26.3`.
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Records payloads and chunk sends.
final class RecordingSink implements SablePayloadSink, SableChunkViewSender {
  final List<(String, String)> payloads = [];
  final List<(String, int, int)> chunks = [];

  @override
  void sendPayload(String playerId, String payloadId, Uint8List body) =>
      payloads.add((playerId, payloadId));

  @override
  void sendChunkAt(String playerId, int blockX, int blockZ) =>
      chunks.add((playerId, blockX, blockZ));

  @override
  void unloadChunkAt(String playerId, int blockX, int blockZ) =>
      chunks.add((playerId, -blockX, -blockZ));

  List<String> payloadsFor(String playerId) =>
      [for (final entry in payloads) if (entry.$1 == playerId) entry.$2];

  /// Only the payloads that change *tracking* state, in order. A first sync
  /// also carries `change_bounds_sublevel` for the plot's initial bounds, which
  /// Java sends too.
  List<String> trackingPayloadsFor(String playerId) => [
    for (final payload in payloadsFor(playerId))
      if (payload == 'sable:start_tracking_sub_level' ||
          payload == 'sable:finalize_sub_level' ||
          payload == 'sable:stop_tracking_sub_level')
        payload,
  ];

  void clear() {
    payloads.clear();
    chunks.clear();
  }
}

final class TestHost implements SubLevelHost {
  final FakeChunkHost chunks;

  TestHost(this.chunks);

  @override
  Iterable<SablePlayer> get players => chunks.players.values;

  @override
  SablePlayer? playerById(String uuid) => chunks.players[uuid];

  @override
  SubLevelLookup get subLevels => throw UnimplementedError();

  @override
  Pose3dc poseForSaving(String subLevelId) => throw UnimplementedError();

  @override
  (double, double, double) centerOfMass(String subLevelId) => throw UnimplementedError();

  @override
  (double, double, double, double, double, double)? velocity(String subLevelId) => null;

  @override
  Map<String, Object?>? readSavedData(String name) => null;

  @override
  void markSavedDataDirty(String name) {}

  @override
  void writeSavedData(String name, Map<String, Object?> data) {}
}

final class NullMassTracker implements MassData {
  @override
  Vector3d getCenterOfMass() => Vector3d();

  @override
  double getInverseMass() => 1.0;

  @override
  bool isInvalid() => false;

  @override
  BoundingBox3ic? getBounds() => null;
}

void main() {
  late FakeLevel level;
  late FakeChunkHost host;
  late ServerSubLevelContainer container;
  late RecordingSink sink;
  late SubLevelTrackingSystem tracking;
  late ServerSubLevel subLevel;

  setUp(() {
    SubLevelContainer.clearAll();
    level = FakeLevel();
    host = FakeChunkHost(level);
    container = ServerSubLevelContainer(
      level,
      host,
      3,
      4,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
    );
    ServerSubLevel.massTrackerFactory = (subLevel) => NullMassTracker();
    SubLevelContainer.register(container);
    container.hostOrNull = TestHost(host);

    sink = RecordingSink();
    tracking = SubLevelTrackingSystem(
      container: container,
      config: SableConfig(subLevelTrackingRange: 100),
      sink: sink,
      chunkView: sink,
    )..nowMillis = () => 1000;

    subLevel = container.allocateSubLevel(
      '00000000-0000-0000-0000-000000000001',
      0,
      0,
      Pose3d(),
    ) as ServerSubLevel;
    subLevel.massTracker = NullMassTracker();
    subLevel.logicalPose.position().set(0, 0, 0);
    // A plot with real bounds: an empty plot legitimately re-sends
    // `change_bounds_sublevel` every tick (its empty box never compares equal
    // to the last networked box), which would drown out the assertions.
    subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 15, 15, 15));
    subLevel.lastNetworkedBoundingBox.setFrom(subLevel.getPlot().getBoundingBox());
  });

  tearDown(SubLevelContainer.clearAll);

  void addPlayer(String uuid, (double, double, double) position) =>
      host.players[uuid] = FakePlayer(uuid, position);

  group('the range is a strict sphere', () {
    test('a player exactly at the range is not tracking', () {
      addPlayer('p1', (100, 0, 0));
      tracking.tick(container);

      expect(subLevel.trackingPlayers, isEmpty);
      expect(sink.payloadsFor('p1'), isEmpty);
    });

    test('a player just inside the range is tracking', () {
      addPlayer('p1', (99.99, 0, 0));
      tracking.tick(container);

      expect(subLevel.trackingPlayers, {'p1'});
      expect(sink.trackingPayloadsFor('p1').first, 'sable:start_tracking_sub_level');
    });

    test('the test is on the whole 3d distance, not the horizontal one', () {
      // 80 horizontally and 80 vertically is 113 blocks: out of range.
      addPlayer('p1', (80, 80, 0));
      tracking.tick(container);

      expect(subLevel.trackingPlayers, isEmpty);
    });

    test('a player inside on every axis is tracking', () {
      // 50 on each axis is 86.6 blocks away: inside a 100 block sphere.
      addPlayer('p1', (50, 50, 50));
      tracking.tick(container);

      expect(subLevel.trackingPlayers, {'p1'});
    });
  });

  group('adding and dropping', () {
    test('a player walking into range gets a full sync once', () {
      addPlayer('p1', (500, 0, 0));
      tracking.tick(container);
      expect(sink.payloadsFor('p1'), isEmpty);

      (host.players['p1']! as FakePlayer).position = (10, 0, 0);
      tracking.tick(container);

      expect(sink.trackingPayloadsFor('p1'), [
        'sable:start_tracking_sub_level',
        'sable:finalize_sub_level',
      ]);

      // A second tick does not repeat the sync.
      sink.clear();
      tracking.tick(container);
      expect(sink.payloadsFor('p1'), isEmpty);
    });

    test('a player walking out of range gets exactly one stop', () {
      addPlayer('p1', (10, 0, 0));
      tracking.tick(container);
      expect(subLevel.trackingPlayers, {'p1'});

      sink.clear();
      (host.players['p1']! as FakePlayer).position = (500, 0, 0);
      tracking.tick(container);

      expect(sink.trackingPayloadsFor('p1'), ['sable:stop_tracking_sub_level']);
      expect(subLevel.trackingPlayers, isEmpty);

      // And nothing more once they are gone.
      sink.clear();
      tracking.tick(container);
      expect(sink.payloadsFor('p1'), isEmpty);
    });

    test('walking back in re-sends the full sync', () {
      addPlayer('p1', (10, 0, 0));
      tracking.tick(container);

      (host.players['p1']! as FakePlayer).position = (500, 0, 0);
      tracking.tick(container);

      sink.clear();
      (host.players['p1']! as FakePlayer).position = (10, 0, 0);
      tracking.tick(container);

      expect(sink.trackingPayloadsFor('p1'), [
        'sable:start_tracking_sub_level',
        'sable:finalize_sub_level',
      ]);
    });

    test('two players are tracked independently', () {
      addPlayer('p1', (10, 0, 0));
      addPlayer('p2', (500, 0, 0));
      tracking.tick(container);

      expect(subLevel.trackingPlayers, {'p1'});

      (host.players['p2']! as FakePlayer).position = (20, 0, 0);
      tracking.tick(container);
      expect(subLevel.trackingPlayers, {'p1', 'p2'});

      (host.players['p1']! as FakePlayer).position = (500, 0, 0);
      sink.clear();
      tracking.tick(container);

      expect(subLevel.trackingPlayers, {'p2'});
      expect(sink.trackingPayloadsFor('p1'), ['sable:stop_tracking_sub_level']);
      expect(sink.payloadsFor('p2'), isEmpty);
    });

    test('a sub-level created while the player is far away is sent when they arrive', () {
      addPlayer('p1', (500, 0, 0));

      final second = container.allocateSubLevel(
        '00000000-0000-0000-0000-000000000002',
        1,
        1,
        Pose3d(),
      ) as ServerSubLevel;
      second.massTracker = NullMassTracker();
      second.logicalPose.position().set(400, 0, 0);
      tracking.tick(container);

      expect(second.trackingPlayers, isEmpty);

      (host.players['p1']! as FakePlayer).position = (390, 0, 0);
      tracking.tick(container);

      expect(second.trackingPlayers, {'p1'});
    });

    test('the range is measured from the logical pose', () {
      addPlayer('p1', (0, 0, 0));
      subLevel.logicalPose.position().set(99, 0, 0);
      tracking.tick(container);
      expect(subLevel.trackingPlayers, {'p1'});

      // The networked (last sent) pose does not move the range.
      subLevel.lastNetworkedPose.position().set(1000, 0, 0);
      sink.clear();
      tracking.tick(container);
      expect(subLevel.trackingPlayers, {'p1'});
      expect(sink.payloadsFor('p1'), isNot(contains('sable:stop_tracking_sub_level')));
    });

    test('a removed sub-level stops tracking its players', () {
      addPlayer('p1', (10, 0, 0));
      tracking.tick(container);
      expect(subLevel.trackingPlayers, {'p1'});

      sink.clear();
      container.removeSubLevelAt(subLevel, SubLevelRemovalReason.removed);

      expect(sink.trackingPayloadsFor('p1'), ['sable:stop_tracking_sub_level']);
      expect(subLevel.trackingPlayers, isEmpty);
    });
  });
}
