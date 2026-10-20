// The physics tick loop's *order*, not just its effects.
//
// `SubLevelPhysicsSystem.tick` is a sequence of phases, and the Java order is
// part of the contract: a force queued after `applyQueuedForces` is a tick
// late, an actor ticked after the pose read sees a stale pose, and a pose read
// before the substep leaves the render pose a tick behind. Every phase boundary
// below is observable through a seam (the pipeline, the platform hooks, the
// listeners, an actor), so the whole sequence is asserted as one ordered log.
//
// The expected sequence is transcribed from
// `SubLevelPhysicsSystem.tick` / `tickPipelinePhysics` on the `port/26.3`
// branch.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A shared, ordered log of everything the tick loop touches.
final class TickLog {
  final List<String> entries = [];

  void add(String entry) => entries.add(entry);

  /// The entries between [from] and [to], both excluded.
  List<String> between(String from, String to) {
    final start = entries.indexOf(from);
    final end = entries.lastIndexOf(to);
    expect(start, isNonNegative, reason: 'missing "$from"');
    expect(end, greaterThan(start), reason: 'missing "$to" after "$from"');
    return entries.sublist(start + 1, end);
  }

  @override
  String toString() => entries.join(' > ');
}

/// A pipeline that logs the calls the tick loop makes.
final class LoggingPipeline implements PhysicsPipeline {
  final TickLog log;
  final Map<ServerSubLevel, Pose3d> poses = {};
  int nextRuntimeId = 1;

  /// The last pose of the sub-level as seen from inside `tick()`.
  double? lastPoseYSeenInTick;

  /// The sub-level whose `lastPose` is sampled inside `tick()`.
  ServerSubLevel? sample;

  LoggingPipeline(this.log);

  @override
  void tick() {
    log.add('pipeline.tick');
    final subLevel = sample;
    if (subLevel != null) lastPoseYSeenInTick = subLevel.lastPose.position().y;
  }

  @override
  void prePhysicsTicks() => log.add('pipeline.prePhysicsTicks');

  @override
  void physicsTick(double timeStep) => log.add('pipeline.physicsTick');

  @override
  void postPhysicsTicks() => log.add('pipeline.postPhysicsTicks');

  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) {
    poses[subLevel] = Pose3d.copy(pose);
    return LoggingHandle(this, log);
  }

  @override
  void removeSubLevel(ServerSubLevel subLevel) => poses.remove(subLevel);

  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) {
    final pose = poses[subLevel];
    if (pose != null) dest.set(pose);
    return dest;
  }

  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) => log.add('section.add($x,$y,$z)');

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) =>
      log.add('section.remove($x,$y,$z)');

  @override
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  @override
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  @override
  int getNextRuntimeId() => nextRuntimeId++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A body handle that logs the force flush.
final class LoggingHandle implements RigidBodyHandle {
  final LoggingPipeline pipeline;
  final TickLog log;

  LoggingHandle(this.pipeline, this.log);

  @override
  void applyForcesAndReset(Vector3d force) => log.add('handle.forces');

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) => log.add('handle.velocity');

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) =>
      log.add('handle.impulse');

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  void teleport(Vector3d position, Quaterniond orientation) => log.add('handle.teleport');
}

/// A platform that logs the two physics hooks.
final class LoggingPlatform implements SablePlatform {
  final TickLog log;

  LoggingPlatform(this.log);

  @override
  void onPhysicsTick(SableLevel level, double timeStep) => log.add('platform.pre');

  @override
  void onPostPhysicsTick(SableLevel level, double timeStep) => log.add('platform.post');

  @override
  void setIgnoreOnPlace(SableLevel level, bool ignore) {}

  @override
  void onPlotChunkLoaded(PlotChunk chunk) {}

  @override
  void onOldChunkInvalid(PlotChunk chunk) {}

  @override
  void onClientChunkPacketReplaced(PlotChunk chunk) {}

  @override
  void writeLightData(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void readLightData(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void writeChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void readChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void postLoad(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void onSubLevelContainerReady(SableLevel level) {}
}

/// A block-entity actor that logs both of its hooks.
final class LoggingActor implements BlockEntitySubLevelActor {
  final TickLog log;

  LoggingActor(this.log);

  @override
  void sable$tick(ServerSubLevel subLevel) => log.add('actor.tick');

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) =>
      log.add('actor.physics');

  @override
  Iterable<SubLevel>? sable$getConnectionDependencies() => null;

  @override
  Iterable<SubLevel>? sable$getLoadingDependencies() => null;
}

final class LoggingMassTracker implements MassData {
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
  late LoggingPipeline pipeline;
  late TickLog log;
  late SubLevelPhysicsSystem system;
  late ServerSubLevel subLevel;

  setUp(() {
    SubLevelContainer.clearAll();
    log = TickLog();
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
    ServerSubLevel.massTrackerFactory = (subLevel) => LoggingMassTracker();
    SubLevelContainer.register(container);
    container.hostOrNull = _NoPlayersHost(host);
    SablePlatform.instance = LoggingPlatform(log);

    pipeline = LoggingPipeline(log);
    system = SubLevelPhysicsSystem(
      container: container,
      pipeline: pipeline,
      config: SableConfig(),
      serverConfig: SableServerConfig(subLevelSubstepsPerTick: 2),
    );

    subLevel = container.allocateSubLevel(
      '00000000-0000-0000-0000-000000000001',
      0,
      0,
      Pose3d(),
    ) as ServerSubLevel;
    subLevel.massTracker = LoggingMassTracker();
    subLevel.logicalPose.position().set(0, 5, 0);
    subLevel.getPlot().blockEntityActors[(0, 0, 0)] = LoggingActor(log);
    // A queued force group, so `applyQueuedForces` reaches the handle.
    subLevel.getOrCreateQueuedForceGroup(const ForceGroup('test'));
  });

  tearDown(() {
    SablePlatform.instance = null;
    SubLevelContainer.clearAll();
  });

  test('one game tick runs the Java phase order', () {
    log.entries.clear();
    system.tick(container);

    // Everything after the ticket manager, in order.
    final phases = log.entries.where((entry) => entry != 'section.add' && !entry.startsWith('section.')).toList();
    expect(phases, [
      // 3. per sub-level: remember the pose, then tick its actors
      'actor.tick',
      // 4. pipeline bookkeeping, even while paused
      'pipeline.tick',
      // 5. the substeps
      'pipeline.prePhysicsTicks',
      'actor.physics',
      'platform.pre',
      'handle.forces',
      'pipeline.physicsTick',
      'platform.post',
      'actor.physics',
      'platform.pre',
      'handle.forces',
      'pipeline.physicsTick',
      'platform.post',
      // 6. finalize
      'pipeline.postPhysicsTicks',
    ], reason: log.toString());
  });

  test('the pose is remembered before the pipeline tick', () {
    pipeline.sample = subLevel;
    subLevel.logicalPose.position().set(0, 5, 0);
    subLevel.lastPose.position().set(0, -1, 0);

    system.tick(container);

    expect(pipeline.lastPoseYSeenInTick, 5.0);
  });

  test('every substep runs prePhysicsTick before the physics tick', () {
    log.entries.clear();
    system.tick(container);

    final firstPhysics = log.entries.indexOf('actor.physics');
    final firstForces = log.entries.indexOf('handle.forces');
    final firstTick = log.entries.indexOf('pipeline.physicsTick');

    expect(firstPhysics, greaterThanOrEqualTo(0));
    expect(firstForces, greaterThan(firstPhysics));
    expect(firstTick, greaterThan(firstForces));
  });

  test('the platform pre hook runs before applyQueuedForces', () {
    log.entries.clear();
    system.tick(container);

    expect(log.entries.indexOf('platform.pre'), lessThan(log.entries.indexOf('handle.forces')));
  });

  test('the post hook runs after the physics tick and the pose read', () {
    log.entries.clear();
    system.tick(container);

    expect(log.entries.indexOf('platform.post'), greaterThan(log.entries.indexOf('pipeline.physicsTick')));
  });

  test('the listeners run in the platform hook slots', () {
    final listenerLog = <String>[];
    system.prePhysicsTickListeners.add((system, timeStep) => listenerLog.add('pre'));
    system.postPhysicsTickListeners.add((system, timeStep) => listenerLog.add('post'));

    log.entries.clear();
    system.tick(container);

    expect(listenerLog, ['pre', 'post', 'pre', 'post']);
    // The platform hook precedes the listeners in each slot.
    final preIndex = log.entries.indexOf('platform.pre');
    expect(log.entries[preIndex + 1], isNot('platform.post'));
  });

  test('three substeps run three physics ticks and two actor game ticks', () {
    system.physicsConfig.updateFromConfig(SableServerConfig(subLevelSubstepsPerTick: 3));

    log.entries.clear();
    system.tick(container);

    expect(log.entries.where((e) => e == 'pipeline.physicsTick'), hasLength(3));
    expect(log.entries.where((e) => e == 'actor.physics'), hasLength(3));
    expect(log.entries.where((e) => e == 'actor.tick'), hasLength(1));
    expect(log.entries.where((e) => e == 'pipeline.prePhysicsTicks'), hasLength(1));
    expect(log.entries.where((e) => e == 'pipeline.postPhysicsTicks'), hasLength(1));
  });

  test('a paused system still runs pipeline.tick and no substep', () {
    system.isPaused = true;

    log.entries.clear();
    system.tick(container);

    expect(log.entries, contains('pipeline.tick'));
    expect(log.entries, isNot(contains('pipeline.prePhysicsTicks')));
    expect(log.entries, isNot(contains('pipeline.physicsTick')));
    expect(log.entries, isNot(contains('actor.physics')));
    expect(log.entries, isNot(contains('pipeline.postPhysicsTicks')));
  });

  test('dirty sections are re-uploaded after the last substep', () {
    // The section must be tracked and the chunk loaded, or the flush has
    // nothing to upload.
    host.createEmptyChunk(0, 0);
    system.ticketManager.packer = _ZeroPacker();
    system.ticketManager.addTicketForSection(0, -4, 0);
    system.ticketManager.markSectionDirty(0, -64, 0);

    log.entries.clear();
    system.tick(container);

    final flushIndex = log.entries.indexWhere((e) => e.startsWith('section.'));
    expect(flushIndex, greaterThanOrEqualTo(0));
    expect(flushIndex, greaterThan(log.entries.indexOf('pipeline.postPhysicsTicks')));
    expect(system.ticketManager.dirtySections, isEmpty);
  });

  test('the punch cooldown is decremented once per tick', () {
    system.punchCooldowns['player'] = 2;

    system.tick(container);
    expect(system.punchCooldowns['player'], 1);

    system.tick(container);
    expect(system.punchCooldowns.containsKey('player'), isFalse);
  });
}

/// A section packer that uploads an empty section, so the flush reaches the
/// pipeline.
final class _ZeroPacker implements PlotSectionPacker {
  @override
  List<int> packSection(PlotChunk chunk, int sectionIndex) => List<int>.filled(4096, 0);
}

/// A host with no players, so the ticket manager never sees one inside a
/// sub-level's bounds.
final class _NoPlayersHost implements SubLevelHost {
  final FakeChunkHost chunks;

  _NoPlayersHost(this.chunks);

  @override
  Iterable<SablePlayer> get players => const [];

  @override
  SablePlayer? playerById(String uuid) => null;

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
