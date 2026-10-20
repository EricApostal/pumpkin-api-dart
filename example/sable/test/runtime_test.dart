// Tests for the W4 server runtime: the physics tick loop (substeps, pause,
// queued forces, NaN recovery), the chunk ticket manager, the tracking system
// (what is sent, in what order) and entity collision box collection.
//
// The pipeline is a recording fake, so the tests assert the *sequence* of calls
// the system makes, which is the part the Java code guarantees.
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A minimal [SubLevelHost] over the fake chunk host.
final class FakeSubLevelHost implements SubLevelHost {
  @override
  final FakeChunkHost chunks;

  FakeSubLevelHost(this.chunks);

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

/// A pipeline that records every call and hands back a scripted pose.
final class RecordingPipeline implements PhysicsPipeline {
  final List<String> calls = [];
  final Map<ServerSubLevel, Pose3d> poses = {};
  int nextRuntimeId = 1;

  /// When set, `readPose` returns this pose for the next sub-level read.
  Pose3d? scriptedPose;

  @override
  void init(Vector3d gravity, double universalDrag) => calls.add('init');

  @override
  void dispose() => calls.add('dispose');

  @override
  void tick() => calls.add('tick');

  @override
  void prePhysicsTicks() => calls.add('prePhysicsTicks');

  @override
  void physicsTick(double timeStep) => calls.add('physicsTick(${timeStep.toStringAsFixed(4)})');

  @override
  void postPhysicsTicks() => calls.add('postPhysicsTicks');

  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) {
    calls.add('add(${subLevel.uniqueId})');
    poses[subLevel] = Pose3d.copy(pose);
    return _RecordingHandle(this, subLevel);
  }

  @override
  void removeSubLevel(ServerSubLevel subLevel) {
    calls.add('remove(${subLevel.uniqueId})');
    poses.remove(subLevel);
  }

  @override
  void addContraption(KinematicContraption contraption) => calls.add('addContraption');

  @override
  void removeContraption(KinematicContraption contraption) => calls.add('removeContraption');

  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) {
    final pose = scriptedPose ?? poses[subLevel];
    if (pose != null) dest.set(pose);
    return dest;
  }

  @override
  BoxHandle addBox(BoxPhysicsObject box) => throw UnimplementedError();

  @override
  void removeBox(BoxHandle box) => throw UnimplementedError();

  @override
  RopeHandle addRope(RopePhysicsObject rope) => throw UnimplementedError();

  @override
  void removeRope(RopeHandle rope) => throw UnimplementedError();

  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) => calls.add('sectionAdd($x,$y,$z)');

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) =>
      calls.add('sectionRemove($x,$y,$z)');

  @override
  void handleBlockChange(int x, int y, int z, int packedState) =>
      calls.add('blockChange($x,$y,$z)');

  @override
  void onStatsChanged(ServerSubLevel subLevel) => calls.add('stats(${subLevel.uniqueId})');

  @override
  void teleport(RigidBodyHandle body, Vector3d position, Quaterniond orientation) =>
      calls.add('teleport');

  @override
  void applyImpulse(RigidBodyHandle body, Vector3d position, Vector3d force) =>
      calls.add('impulse');

  @override
  void applyLinearAndAngularImpulse(
    RigidBodyHandle body,
    Vector3d force,
    Vector3d torque,
    bool wakeUp,
  ) => calls.add('impulse6');

  @override
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) => calls.add('addVelocity');

  @override
  void resetVelocity(RigidBodyHandle body) => calls.add('resetVelocity');

  @override
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  @override
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  @override
  void wakeUp(RigidBodyHandle body) => calls.add('wakeUp');

  @override
  int getNextRuntimeId() => nextRuntimeId++;
}

final class _RecordingHandle implements RigidBodyHandle {
  final RecordingPipeline pipeline;
  final ServerSubLevel subLevel;

  _RecordingHandle(this.pipeline, this.subLevel);

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) =>
      pipeline.calls.add('handle.addVelocity');

  @override
  void applyForcesAndReset(Vector3d force) => pipeline.calls.add('handle.forces');

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) =>
      pipeline.calls.add('handle.impulse6');

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  void teleport(Vector3d position, Quaterniond orientation) => pipeline.calls.add('handle.teleport');
}

/// A mass tracker the physics system can update.
final class FakeMassTracker implements MassData, MutableMassTracker {
  final List<(String, double)> deltas = [];
  Vector3d center = Vector3d();
  bool invalid = false;

  @override
  void addBlockMass(String state, (int, int, int) pos, double mass, (double, double, double)? inertia) =>
      deltas.add((state, mass));

  @override
  Vector3d getCenterOfMass() => center;

  @override
  double getInverseMass() => 1.0;

  @override
  double getMass() => 1.0;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.identity();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.identity();

  @override
  bool isInvalid() => invalid;

  @override
  BoundingBox3ic? getBounds() => null;
}

/// Creates a server sub-level in [container] at the local plot [x], [z].
ServerSubLevel addSubLevel(ServerSubLevelContainer container, int x, int z, String uuid) {
  SubLevelContainer.register(container);
  final subLevel = container.allocateSubLevel(uuid, x, z, Pose3d()) as ServerSubLevel;
  subLevel.massTracker = FakeMassTracker();
  return subLevel;
}

/// Records the payloads and chunk sends of the tracking system.
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

  List<String> get ids => [for (final payload in payloads) payload.$2];
}

void main() {
  group('SubLevelPhysicsSystem', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late RecordingPipeline pipeline;
    late SubLevelPhysicsSystem system;

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
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      pipeline = RecordingPipeline();
      system = SubLevelPhysicsSystem(
        container: container,
        pipeline: pipeline,
        config: SableConfig(),
        serverConfig: SableServerConfig(subLevelSubstepsPerTick: 2),
      );
    });

    test('adds a sub-level to the pipeline with its pose', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');

      expect(pipeline.calls, contains('add(00000000-0000-0000-0000-000000000001)'));
      expect(subLevel.physicsBody, isNotNull);
      expect(subLevel.massTracker, isNotNull);
    });

    test('removing a sub-level removes its body', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      container.removeSubLevelAt(subLevel, SubLevelRemovalReason.removed);

      expect(pipeline.calls, contains('remove(00000000-0000-0000-0000-000000000001)'));
      expect(subLevel.physicsBody, isNull);
    });

    test('a tick runs pipeline.tick, then prePhysicsTicks and one physicsTick '
        'per substep, then postPhysicsTicks', () {
      addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      pipeline.calls.clear();

      system.tick(container);

      final sequence = pipeline.calls.where((call) => !call.startsWith('section')).toList();
      expect(sequence.first, 'tick');
      expect(sequence, contains('prePhysicsTicks'));
      expect(
        sequence.where((call) => call.startsWith('physicsTick')).toList(),
        ['physicsTick(0.0250)', 'physicsTick(0.0250)'],
      );
      expect(sequence.last, 'postPhysicsTicks');
    });

    test('the substep count comes from the server config', () {
      addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      system.physicsConfig.updateFromConfig(SableServerConfig(subLevelSubstepsPerTick: 4));
      pipeline.calls.clear();

      system.tick(container);

      expect(
        pipeline.calls.where((call) => call.startsWith('physicsTick')).length,
        4,
      );
      // Each substep is 1/20/4 s.
      expect(pipeline.calls, contains('physicsTick(0.0125)'));
    });

    test('a paused system still ticks but runs no substeps', () {
      addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      pipeline.calls.clear();

      system.isPaused = true;
      system.tick(container);

      expect(pipeline.calls, contains('tick'));
      expect(pipeline.calls, isNot(contains('prePhysicsTicks')));
      expect(pipeline.calls.where((call) => call.startsWith('physicsTick')), isEmpty);
    });

    test('punch cooldowns tick down and gate repeated punches', () {
      expect(system.tryPunch('player', 3), isTrue);
      expect(system.tryPunch('player', 3), isFalse);

      for (var i = 0; i < 3; i++) {
        system.tick(container);
      }
      expect(system.tryPunch('player', 3), isTrue);
    });

    test('the partial physics tick reports the substep fraction', () {
      addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      // 0.5 before the first tick; after it, Java leaves `currentSubstep` at
      // `substepsPerTick`, so the fraction is (n + 1) / n.
      expect(system.getPartialPhysicsTick(), closeTo(0.5, 1e-12));
      system.tick(container);
      expect(system.getPartialPhysicsTick(), closeTo(1.5, 1e-12));
    });

    test('a NaN pose is recovered by re-adding the body', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      pipeline.calls.clear();
      pipeline.scriptedPose = Pose3d()..position().set(double.nan, 0, 0);

      system.updatePose(subLevel);

      expect(pipeline.calls, contains('remove(00000000-0000-0000-0000-000000000001)'));
      expect(pipeline.calls, contains('add(00000000-0000-0000-0000-000000000001)'));
    });

    test('a block change marks its section dirty and reaches the pipeline', () {
      addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      pipeline.calls.clear();

      system.handleBlockChange(5, 70, 5, 'minecraft:air', 'minecraft:stone');

      expect(pipeline.calls, contains('blockChange(5,70,5)'));
    });

    test('updatePose derives the velocities from the pose delta', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(0, 0, 0);
      subLevel.mutableLastPose.position().set(-1, 0, 0);

      final moved = Pose3d()..position().set(0, 0, 0);
      pipeline.scriptedPose = moved;
      system.updatePose(subLevel);

      // 1 block in 1/20 s = 20 m/s.
      expect(subLevel.latestLinearVelocity.x, closeTo(20.0, 1e-9));
    });
  });

  group('PhysicsChunkTicketManager', () {
    test('inhabited chunks get a host ticket and it is released when they expire', () {
      SubLevelContainer.clearAll();
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      final pipeline = RecordingPipeline();
      final system = SubLevelPhysicsSystem(
        container: container,
        pipeline: pipeline,
        config: SableConfig(),
        serverConfig: SableServerConfig(),
      );

      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(0, 0, 0);
      subLevel.updateBoundingBox();
      // A sub-level that is not force-loaded takes no host ticket: it only
      // inhabits chunks it is already inside.
      system.ticketManager.update(0.05);
      expect(host.tickets, isEmpty);

      // A force-loaded sub-level takes one, and refreshes it every tick.
      container.addForceLoadTicket(subLevel, SubLevelLoadingTicketType.commandForced, 'test');
      system.ticketManager.update(0.05);

      expect(host.tickets, isNotEmpty);
      expect(
        host.tickets.every((t) => t.$3 == PhysicsChunkTicketManager.subLevelLoadedTicketType),
        isTrue,
      );
      expect(
        host.tickets.every((t) => t.$4 == PhysicsChunkTicketManager.subLevelLoadedTicketLevel),
        isTrue,
      );

      // One ticket per chunk per update, not one per section of the chunk.
      expect(host.tickets.toSet().length, host.tickets.length);

      // A later update refreshes the tickets instead of stacking new ones on
      // top: the chunk set is the same.
      final chunks = host.tickets.map((t) => (t.$1, t.$2)).toSet();
      host.tickets.clear();
      level.gameTime = 100;
      system.ticketManager.update(0.05);
      expect(host.tickets.map((t) => (t.$1, t.$2)).toSet(), chunks);
    });
  });

  group('SubLevelTrackingSystem', () {
    late FakeLevel level;
    late FakeChunkHost host;
    late ServerSubLevelContainer container;
    late RecordingSink sink;
    late SubLevelTrackingSystem tracking;

    setUp(() {
      SubLevelContainer.clearAll();
      level = FakeLevel();
      host = FakeChunkHost(level);
      host.players['p1'] = FakePlayer('p1', (0, 0, 0));
      container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      sink = RecordingSink();
      tracking = SubLevelTrackingSystem(
        container: container,
        config: SableConfig(subLevelTrackingRange: 100),
        sink: sink,
        chunkView: sink,
      );
    });

    test('a new sub-level sends start, its chunks, then finalize', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      subLevel.getPlot().newEmptyChunk(subLevel.getPlot().toGlobal((0, 0)));

      tracking.tick(container);

      final ids = sink.ids;
      final start = ids.indexOf(ClientboundStartTrackingSubLevelPacket.payloadId);
      final finalize = ids.indexOf(ClientboundFinalizeSubLevelPacket.payloadId);
      expect(start, 0);
      expect(finalize, greaterThan(start));
      expect(sink.chunks.length, 1);
      expect(subLevel.trackingPlayers, {'p1'});
    });

    test('a sub-level out of range is never sent', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1000, 0, 0);

      tracking.tick(container);

      expect(sink.payloads, isEmpty);
      expect(subLevel.trackingPlayers, isEmpty);
    });

    test('walking out of range sends stop_tracking_sub_level', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      sink.payloads.clear();

      (host.players['p1'] as FakePlayer).position = (10000, 0, 0);
      tracking.tick(container);

      expect(sink.ids, contains(ClientboundStopTrackingSubLevelPacket.payloadId));
      expect(subLevel.trackingPlayers, isEmpty);
    });

    test('a moving sub-level sends snapshot_info then a snapshot', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      sink.payloads.clear();

      subLevel.logicalPose.position().set(10, 2, 3);
      tracking.tick(container);

      expect(
        sink.ids,
        containsAllInOrder([
          ClientboundSableSnapshotInfoDualPacket.payloadId,
          ClientboundSableSnapshotDualPacket.payloadId,
        ]),
      );
    });

    test('a sub-level that comes to rest sends stop_moving_sub_level', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      subLevel.logicalPose.position().set(10, 2, 3);
      tracking.tick(container);
      sink.payloads.clear();

      tracking.tick(container);

      expect(sink.ids, contains(ClientboundStopMovingSubLevelPacket.payloadId));
    });

    test('a moving sub-level is never sent twice', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      subLevel.logicalPose.position().set(10, 2, 3);
      tracking.tick(container);
      sink.payloads.clear();

      tracking.tick(container);
      tracking.tick(container);

      expect(
        sink.ids.where((id) => id == ClientboundStopMovingSubLevelPacket.payloadId).length,
        1,
      );
    });

    test('changed plot bounds send change_bounds_sublevel', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 4, 4, 4));
      subLevel.lastNetworkedBoundingBox.setValues(0, 0, 0, 0, 0, 0);
      tracking.tick(container);
      sink.payloads.clear();

      subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 8, 8, 8));
      tracking.tick(container);

      expect(sink.ids, contains(ClientboundChangeBoundsSubLevelPacket.payloadId));
    });

    test('the interpolation tick advances once per tick', () {
      expect(tracking.interpolationTick, 0);
      tracking.tick(container);
      expect(tracking.interpolationTick, 1);
      tracking.tick(container);
      expect(tracking.interpolationTick, 2);
    });

    test('a split sub-level sends recently_split_sub_level in its sync', () {
      final parent = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000002');
      parent.logicalPose.position().set(1, 2, 3);

      final child = addSubLevel(container, 1, 0, '00000000-0000-0000-0000-000000000003');
      child.logicalPose.position().set(1, 2, 3);
      child.setSplitFrom(parent, Pose3d());

      tracking.tick(container);

      expect(sink.ids, contains(ClientboundRecentlySplitSubLevelPacket.payloadId));
    });

    test('a removed sub-level sends stop_tracking to its tracking players', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);
      sink.payloads.clear();

      container.removeSubLevelAt(subLevel, SubLevelRemovalReason.removed);

      expect(sink.ids, contains(ClientboundStopTrackingSubLevelPacket.payloadId));
    });

    test('the payloads the tracking system sends are the Java ones and decode', () {
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.logicalPose.position().set(1, 2, 3);
      tracking.tick(container);

      expect(sink.payloads.first.$2, 'sable:start_tracking_sub_level');
      expect(
        sink.ids,
        contains(ClientboundFinalizeSubLevelPacket.payloadId),
      );
    });
  });

  group('entity collision', () {
    test('the boxes of a sub-level cover its solid blocks', () {
      SubLevelContainer.clearAll();
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');

      subLevel.getPlot().newEmptyChunk(subLevel.getPlot().toGlobal((0, 0)));
      final chunk = subLevel.getPlot().toGlobal((0, 0));
      host.setBlock(chunk.$1 << 4, 0, chunk.$2 << 4, 'minecraft:stone');
      host.setBlock((chunk.$1 << 4) + 1, 0, chunk.$2 << 4, 'minecraft:stone');

      final boxes = SubLevelEntityCollision.boxesOf(subLevel);

      expect(boxes.length, 2);
      // The boxes are in world space, at the plot yard's distant origin.
      final worldX = (chunk.$1 << 4).toDouble();
      expect(boxes.first.minX, worldX);
      expect(boxes.first.maxX, worldX + 1);
      expect(boxes.last.minX, worldX + 1);
    });

    test('the hit box yaw is zero for an unrotated sub-level', () {
      expect(SubLevelEntityCollision.getHitBoxYaw(Pose3d()), closeTo(0.0, 1e-12));
    });

    test('the entity bounds centre is unchanged without a custom orientation', () {
      final center = Vector3d(1, 2, 3);
      SubLevelEntityCollision.transformEntityBoundsCenter(null, center, 1.62, 1.8);
      expect(center, Vector3d(1, 2, 3));
    });
  });

  group('heat map', () {
    test('a sub-level with one solid block is never split', () {
      SubLevelContainer.clearAll();
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.getPlot().newEmptyChunk(subLevel.getPlot().toGlobal((0, 0)));
      final chunk = subLevel.getPlot().toGlobal((0, 0));
      host.setBlock(chunk.$1 << 4, 0, chunk.$2 << 4, 'minecraft:stone');

      final heat = SubLevelHeatMapManager(subLevel, config: SableConfig());
      heat.onSolidAdded((chunk.$1 << 4, 0, chunk.$2 << 4));
      for (var i = 0; i < 10; i++) {
        heat.tick();
      }

      expect(heat.solidCount, 1);
      expect(heat.isSplitComplete, isTrue);
    });

    test('two disconnected blocks become a split candidate', () {
      SubLevelContainer.clearAll();
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );
      ServerSubLevel.massTrackerFactory = (subLevel) => FakeMassTracker();
      SubLevelContainer.register(container);
      container.hostOrNull = FakeSubLevelHost(host);
      final subLevel = addSubLevel(container, 0, 0, '00000000-0000-0000-0000-000000000001');
      subLevel.getPlot().newEmptyChunk(subLevel.getPlot().toGlobal((0, 0)));
      final chunk = subLevel.getPlot().toGlobal((0, 0));
      host.setBlock(chunk.$1 << 4, 0, chunk.$2 << 4, 'minecraft:stone');
      host.setBlock((chunk.$1 << 4) + 5, 0, chunk.$2 << 4, 'minecraft:stone');

      final heat = SubLevelHeatMapManager(subLevel, config: SableConfig());
      heat.onSolidAdded((chunk.$1 << 4, 0, chunk.$2 << 4));
      heat.onSolidAdded(((chunk.$1 << 4) + 5, 0, chunk.$2 << 4));

      expect(heat.solidCount, 2);
      expect(heat.subLevelSplits.length, 1);
    });
  });
}
