// Chunk ticket lifetime: the expiry windows of `PhysicsChunkTicketManager`.
//
// The Java manager has two independent ticket maps with two independent
// expiries, and both windows are `lastInhabitedTick < gameTime - 20`:
//
//  * `physicsChunks` — the sections uploaded to the pipeline. A section is
//    dropped when it is stale **and** it does not belong to a plot, or as soon
//    as its chunk stops being loaded. Dropping it tells the pipeline to forget
//    the section (`handleChunkSectionRemoval`).
//  * `forcedInhabitedChunks` — the host tickets that keep a force-loaded
//    sub-level's chunks loaded. When the last ticket on a chunk goes stale the
//    host ticket is released.
//
// Both windows are inclusive on the boundary: a ticket last refreshed at
// `gameTime - 20` survives, at `gameTime - 21` it expires.
//
// Transcribed from `PhysicsChunkTicketManager.update`,
// `expirePhysicsChunkTickets` and `expireForcedInhabitedChunks` on
// `port/26.3`.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Records the section calls and hands back a body for each sub-level.
final class TicketPipeline implements PhysicsPipeline {
  final List<String> calls = [];
  int nextRuntimeId = 1;

  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) => calls.add('add($x,$y,$z)');

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) =>
      calls.add('remove($x,$y,$z)');

  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) => _Handle(this);

  @override
  void removeSubLevel(ServerSubLevel subLevel) {}

  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) => dest;

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

final class _Handle implements RigidBodyHandle {
  final TicketPipeline pipeline;

  _Handle(this.pipeline);

  @override
  void applyForcesAndReset(Vector3d force) {}

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {}

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}
}

/// A chunk host that can report individual chunks as unloaded.
final class UnloadableHost extends FakeChunkHost {
  final Set<(int, int)> unloaded = {};

  UnloadableHost(super.level);

  @override
  bool isChunkLoadedEnough(int x, int z) => !unloaded.contains((x, z));
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
  late UnloadableHost host;
  late ServerSubLevelContainer container;
  late TicketPipeline pipeline;
  late SubLevelPhysicsSystem system;
  late ServerSubLevel subLevel;

  setUp(() {
    SubLevelContainer.clearAll();
    level = FakeLevel()..gameTime = 0;
    host = UnloadableHost(level);
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

    pipeline = TicketPipeline();
    system = SubLevelPhysicsSystem(
      container: container,
      pipeline: pipeline,
      config: SableConfig(),
      serverConfig: SableServerConfig(subLevelSubstepsPerTick: 1),
    );

    subLevel = container.allocateSubLevel(
      '00000000-0000-0000-0000-000000000001',
      0,
      0,
      Pose3d(),
    ) as ServerSubLevel;
    subLevel.massTracker = NullMassTracker();
    // A one-chunk plot, so the sub-level inhabits exactly one section.
    subLevel.getPlot().setBoundingBox(BoundingBox3i.values(0, 0, 0, 15, 15, 15));
    subLevel.updateBoundingBox();
  });

  tearDown(SubLevelContainer.clearAll);

  /// A section position far outside the plot yard.
  const (int, int, int) outsideSection = (99999, 0, 0);

  group('physics chunk tickets', () {
    test('a section last used 20 ticks ago survives', () {
      system.ticketManager.addTicketForSection(99999, 0, 0);
      level.gameTime = 20;

      system.ticketManager.update(0.05);

      expect(system.ticketManager.trackedSections, contains(outsideSection));
      expect(pipeline.calls.where((call) => call.startsWith('remove')), isEmpty);
    });

    test('a section last used 21 ticks ago is dropped and forgotten', () {
      system.ticketManager.addTicketForSection(99999, 0, 0);
      level.gameTime = 21;

      system.ticketManager.update(0.05);

      expect(system.ticketManager.trackedSections, isNot(contains(outsideSection)));
      expect(pipeline.calls, contains('remove(99999,0,0)'));
    });

    test('a section on a plot is kept however old it is', () {
      final plotChunk = subLevel.getPlot().getChunkMin();
      system.ticketManager.addTicketForSection(plotChunk.$1, 0, plotChunk.$2);
      level.gameTime = 10_000;

      system.ticketManager.update(0.05);

      expect(
        system.ticketManager.trackedSections,
        contains((plotChunk.$1, 0, plotChunk.$2)),
      );
    });

    test('a section whose chunk stopped being loaded is dropped at once', () {
      system.ticketManager.addTicketForSection(99999, 0, 0);
      host.unloaded.add((99999, 0));
      // Not stale: a fresh ticket.
      level.gameTime = 0;

      system.ticketManager.update(0.05);

      expect(system.ticketManager.trackedSections, isNot(contains(outsideSection)));
      expect(pipeline.calls, contains('remove(99999,0,0)'));
    });

    test('a section a live sub-level keeps overlapping is refreshed', () {
      for (final tick in [0, 10, 20, 21, 40, 41]) {
        level.gameTime = tick;
        system.ticketManager.update(0.05);
      }

      // The plot's own section was uploaded on the first tick and refreshed
      // every tick since, so it is still tracked.
      expect(system.ticketManager.trackedSections, isNotEmpty);
      expect(
        pipeline.calls.where((call) => call.startsWith('remove')),
        isEmpty,
      );
    });
  });

  group('forced inhabited chunk tickets', () {
    test('a force-loaded sub-level keeps a host ticket and never expires', () {
      container.addForceLoadTicket(
        subLevel,
        SubLevelLoadingTicketType.commandForced,
        const Object(),
      );

      for (final tick in [0, 10, 20, 21, 100]) {
        level.gameTime = tick;
        system.ticketManager.update(0.05);
      }

      expect(host.tickets, isNotEmpty);
      expect(host.tickets.every((ticket) => ticket.$3 == 'sable:sub_level_loaded'), isTrue);
      expect(system.ticketManager.forcedInhabitedChunks, isNotEmpty);
    });

    test('the host ticket is released 21 ticks after the last refresh', () {
      final ticket = container.addForceLoadTicket(
        subLevel,
        SubLevelLoadingTicketType.commandForced,
        const Object(),
      );
      expect(ticket, isTrue);

      level.gameTime = 0;
      system.ticketManager.update(0.05);
      expect(host.tickets, isNotEmpty);

      // The force-load goes away, so nothing refreshes the ticket.
      container.removeForceLoadTicket(
        subLevel,
        SubLevelLoadingTicketType.commandForced,
        const Object(),
      );

      level.gameTime = 20;
      system.ticketManager.update(0.05);
      expect(host.tickets, isNotEmpty, reason: 'the 20 tick window is inclusive');

      level.gameTime = 21;
      system.ticketManager.update(0.05);
      expect(host.tickets, isEmpty);
      expect(system.ticketManager.forcedInhabitedChunks, isEmpty);
    });

    test('the ticket level is entity ticking', () {
      container.addForceLoadTicket(
        subLevel,
        SubLevelLoadingTicketType.commandForced,
        const Object(),
      );
      level.gameTime = 0;
      system.ticketManager.update(0.05);

      expect(host.tickets.first.$4, PhysicsChunkTicketManager.subLevelLoadedTicketLevel);
    });
  });
}
