// The sub-level lifecycle state machines: the ticket loading system and the
// holding chunk map (what unloads together, what is saved where).
//
// Java: `sable/common/.../api/sublevel/SubLevelTicketLoadingSystem.java` and
// `sable/common/.../sublevel/storage/holding/SubLevelHoldingChunkMap.java`.
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

const String uuidA = '00000000-0000-0000-0000-00000000000a';
const String uuidB = '00000000-0000-0000-0000-00000000000b';

final class _Mass implements MassData {
  @override
  Vector3d getCenterOfMass() => Vector3d();

  @override
  double getInverseMass() => 1.0;

  @override
  double getMass() => 1.0;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.identity();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.identity();

  @override
  bool isInvalid() => false;

  @override
  BoundingBox3ic? getBounds() => null;
}

/// A pipeline that records the velocity it was given.
final class _VelocityPipeline implements PhysicsPipeline {
  Vector3d? linear;
  Vector3d? angular;

  @override
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) {
    linear = Vector3d.copy(linearVelocity);
    angular = Vector3d.copy(angularVelocity);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A body handle that does nothing.
final class _Body implements RigidBodyHandle {
  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => dest ?? Vector3d();

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => dest ?? Vector3d();

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {}

  @override
  void applyForcesAndReset(ForceTotal forceTotal) {}

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) {}

  @override
  void teleport(Vector3d position, Quaterniond orientation) {}

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  bool get isValid => true;
}

/// An in-memory file store, so the holding map can save and reload.
final class _Files implements SableFileStore {
  final Map<String, Uint8List> files = {};

  @override
  bool exists(String path) => files.containsKey(path);

  @override
  List<int> readBytes(String path) => files[path] ?? (throw StateError('missing $path'));

  @override
  void writeBytes(String path, List<int> bytes) => files[path] = Uint8List.fromList(bytes);

  @override
  void delete(String path) => files.remove(path);

  @override
  void createDirectory(String path) {}

  @override
  List<String> list(String path) => [
    for (final key in files.keys)
      if (key.startsWith('$path/')) key.substring(path.length + 1),
  ];
}

ServerSubLevelContainer makeContainer(FakeLevel level, FakeChunkHost host) {
  final container = ServerSubLevelContainer(
    level,
    host,
    3,
    4,
    SubLevelContainer.defaultOrigin,
    SubLevelContainer.defaultOrigin,
  );
  SubLevelContainer.register(container);
  return container;
}

ServerSubLevel addSubLevel(ServerSubLevelContainer container, int x, int z, String uuid) {
  final subLevel = container.allocateSubLevel(uuid, x, z, Pose3d()) as ServerSubLevel;
  subLevel.massTracker = _Mass();
  return subLevel;
}

/// Gives [subLevel] a one-block plot bounds at [worldMin] and recomputes its
/// world bounds. Plot bounds are stored in world block coordinates
/// (`LevelPlot.updateBoundingBox` moves the chunk box by its global chunk
/// position), so no chunk plumbing is needed.
void giveBounds(ServerSubLevel subLevel, int x, int y, int z) {
  subLevel.getPlot().setBoundingBox(BoundingBox3i.values(x, y, z, x + 1, y + 1, z + 1));
  subLevel.updateBoundingBox();
}

void main() {
  setUp(() {
    SubLevelContainer.clearAll();
    ServerSubLevel.packetSink = null;
  });

  group('SubLevelTicketLoadingSystem', () {
    test('a sub-level with tickets becomes active when it is added', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);

      final ticket = SubLevelLoadingTicket(
        SubLevelLoadingTicketType.commandForced,
        uuidA,
        const Object(),
      );
      container.allTickets[uuidA] = SubLevelTicketInfo(null, {ticket});

      SubLevelTicketLoadingSystem(container).onSubLevelAdded(subLevel);

      expect(container.activeTickets[subLevel], contains(ticket));
    });

    test('a sub-level without tickets does not become active', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      container.allTickets[uuidA] = SubLevelTicketInfo();

      SubLevelTicketLoadingSystem(container).onSubLevelAdded(subLevel);
      expect(container.activeTickets, isEmpty);
    });

    test('unloading keeps the ticket info and records the serialization pointer', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      final pointer = GlobalSavedSubLevelPointer(1, 2, 3, 4);
      subLevel.setLastSerializationPointer(pointer);

      final ticket = SubLevelLoadingTicket(
        SubLevelLoadingTicketType.commandForced,
        uuidA,
        const Object(),
      );
      final info = SubLevelTicketInfo(null, {ticket});
      container.allTickets[uuidA] = info;
      container.activeTickets[subLevel] = {ticket};

      SubLevelTicketLoadingSystem(container)
          .onSubLevelRemoved(subLevel, SubLevelRemovalReason.unloaded);

      expect(container.activeTickets, isEmpty);
      expect(container.allTickets[uuidA], same(info));
      expect(info.pointer, same(pointer));
      expect(info.tickets, contains(ticket));
    });

    test('a removal drops the active set but keeps the saved ticket', () {
      // Deliberate divergence from Java, which drops both: a ticket is the only
      // pointer that can load the sub-level back, so a transient failure (a
      // tracker that reads empty for one tick) would otherwise destroy the last
      // way to recover the ship. The explicit delete path opts out through
      // `forgetTickets`.
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      final ticket = SubLevelLoadingTicket(
        SubLevelLoadingTicketType.commandForced,
        uuidA,
        const Object(),
      );
      container.allTickets[uuidA] = SubLevelTicketInfo(null, {ticket});
      container.activeTickets[subLevel] = {ticket};

      SubLevelTicketLoadingSystem(container)
          .onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);

      expect(container.activeTickets, isEmpty);
      expect(container.allTickets.keys, contains(uuidA));
    });

    test('an explicit delete drops the saved ticket too', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      final ticket = SubLevelLoadingTicket(
        SubLevelLoadingTicketType.commandForced,
        uuidA,
        const Object(),
      );
      container.allTickets[uuidA] = SubLevelTicketInfo(null, {ticket});
      container.activeTickets[subLevel] = {ticket};
      container.forgetTickets(uuidA);

      SubLevelTicketLoadingSystem(container)
          .onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);

      expect(container.activeTickets, isEmpty);
      expect(container.allTickets, isEmpty);
    });

    test('a non-server sub-level is ignored', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = TestContainer(level, host);
      SubLevelContainer.register(container);
      final subLevel = container.allocateSubLevel('t', 0, 0, Pose3d());

      // Neither call throws, and nothing is recorded.
      SubLevelTicketLoadingSystem(
        ServerSubLevelContainer(
          level,
          host,
          3,
          4,
          SubLevelContainer.defaultOrigin,
          SubLevelContainer.defaultOrigin,
        ),
      )
        ..onSubLevelAdded(subLevel)
        ..onSubLevelRemoved(subLevel, SubLevelRemovalReason.removed);
    });
  });

  group('SubLevelHoldingChunkMap', () {
    test('pack and unpack round trip, including negative coordinates', () {
      for (final pos in [(0, 0), (1, -1), (-12345, 67890), (1 << 20, -(1 << 20))]) {
        expect(SubLevelHoldingChunkMap.unpack(SubLevelHoldingChunkMap.pack(pos.$1, pos.$2)), pos);
      }
    });

    test('updateChunkStatus replaces a load with an unload of the same chunk', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final map = SubLevelHoldingChunkMap(
        container,
        host,
        SubLevelStorage(_Files(), 'world/sublevels', JsonSubLevelCodec()),
      );

      map.updateChunkStatus(1, 2, true);
      expect(map.chunksToLoad, {SubLevelHoldingChunkMap.pack(1, 2)});
      expect(map.chunksToUnload, isEmpty);

      map.updateChunkStatus(1, 2, false);
      expect(map.chunksToLoad, isEmpty);
      expect(map.chunksToUnload, {SubLevelHoldingChunkMap.pack(1, 2)});

      map.updateChunkStatus(1, 2, true);
      expect(map.chunksToUnload, isEmpty);
    });

    test('moveToUnloaded moves the whole dependency chain into holding', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final a = addSubLevel(container, 0, 0, uuidA);
      final b = addSubLevel(container, 1, 0, uuidB);

      // Two sub-levels whose world bounds overlap are loading dependencies of
      // each other (`SubLevelHelper.getLoadingDependencyChain`), so unloading
      // one must unload both — `SubLevelHoldingChunkMap.java:615`.
      giveBounds(a, 0, 0, 0);
      giveBounds(b, 0, 0, 0);
      expect(a.boundingBox.intersects(b.boundingBox), isTrue);

      final map = SubLevelHoldingChunkMap(
        container,
        host,
        SubLevelStorage(_Files(), 'world/sublevels', JsonSubLevelCodec()),
      );
      map.moveToUnloaded(a, (0, 0));

      expect(container.getAllSubLevels(), isEmpty);
      expect(map.allHoldingSubLevels.keys, containsAll([uuidA, uuidB]));
      expect(map.loadedHoldingChunks[SubLevelHoldingChunkMap.pack(0, 0)]!.loadedHoldingSubLevels.keys,
          containsAll([uuidA, uuidB]));
    });

    test('moveToUnloaded on a lone sub-level moves only it', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final a = addSubLevel(container, 0, 0, uuidA);
      final b = addSubLevel(container, 1, 0, uuidB);
      giveBounds(a, 0, 0, 0);
      giveBounds(b, 1000, 0, 0);

      final map = SubLevelHoldingChunkMap(
        container,
        host,
        SubLevelStorage(_Files(), 'world/sublevels', JsonSubLevelCodec()),
      );
      map.moveToUnloaded(a, (0, 0));

      expect(container.getAllSubLevels(), hasLength(1));
      expect(map.allHoldingSubLevels.keys, [uuidA]);
      expect(map.getHoldingSubLevel(uuidA), isNotNull);
      expect(map.getHoldingSubLevel(uuidB), isNull);
      expect(map.holdingCount, 1);
    });

    test('the holding chunk records the sub-level pointers when it saves', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final a = addSubLevel(container, 0, 0, uuidA);
      giveBounds(a, 0, 0, 0);

      final map = SubLevelHoldingChunkMap(
        container,
        host,
        SubLevelStorage(_Files(), 'world/sublevels', JsonSubLevelCodec()),
      );
      map.moveToUnloaded(a, (0, 0));

      final chunk = map.loadedHoldingChunks[SubLevelHoldingChunkMap.pack(0, 0)]!;
      expect(chunk.getLoadedHoldingSubLevels(), hasLength(1));
      expect(chunk.getLoadedHoldingSubLevels().single.data.uuid, uuidA);
    });
  });

  group('SubLevelAssemblyHelper.kickFromContainingSubLevel', () {
    test('the kick uses ω × r + v and leaves the input velocities untouched', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      final pipeline = _VelocityPipeline();
      final system = SubLevelPhysicsSystem(
        container: container,
        pipeline: pipeline,
        config: SableConfig(),
        serverConfig: SableServerConfig(),
      );
      subLevel.physicsBody = _Body();

      subLevel.pose.position().set(2, 0, 0);
      final containingPose = Pose3d()..position().set(10, 0, 0);
      final linear = Vector3d(0.5, 0, 0);
      final angular = Vector3d(0, 1, 0);

      SubLevelAssemblyHelper.kickFromContainingSubLevel(
        system,
        subLevel,
        linear,
        angular,
        containingPose,
        null,
      );

      // The position is transformed once: 2 → 12.
      expect(subLevel.logicalPose.position(), Vector3d(12, 0, 0));
      // r = 12 − 10 = 2, ω × r = (0,1,0) × (2,0,0) = (0,0,−2); + v = (0.5,0,−2).
      expect(pipeline.linear, Vector3d(0.5, 0, -2));
      // Regression: the cross product used to be written into `angular`, so the
      // angular argument arrived as (0, 0, −2) instead of (0, 1, 0).
      expect(pipeline.angular, Vector3d(0, 1, 0));
      expect(angular, Vector3d(0, 1, 0));
      expect(linear, Vector3d(0.5, 0, 0));
    });
  });

  group('SubLevelDataAccessor', () {
    test('reads and writes the user-data tag', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      subLevel.setName('Boat');
      final accessor = SubLevelDataAccessor(subLevel);

      expect(accessor.getData(), isEmpty);
      accessor.setData({'x': 1});
      expect(accessor.getData(), {'x': 1});
      expect(accessor.getModifiedSuccess(), 'Modified the data of Boat');
      expect(accessor.getPrintSuccess('tag'), 'The data of Boat is: tag');
      expect(accessor.getPrintSuccessAtPath('a.b', 0.5, 3), 'a.b of Boat is 3 (scaled by 0.50)');
    });

    test('falls back to the uuid when the sub-level has no name', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final container = makeContainer(level, host);
      final subLevel = addSubLevel(container, 0, 0, uuidA);
      expect(SubLevelDataAccessor(subLevel).getModifiedSuccess(), 'Modified the data of $uuidA');
    });
  });

  group('SableCommandState', () {
    test('uninstalled resolves with a named host gap', () {
      final state = SableCommandState.uninstalled();
      expect(() => state.levelOf(null), throwsA(isA<StateError>()));
      expect(
        () => state.levelOf(null),
        throwsA(predicate((e) => e.toString().contains('HOST GAP'))),
      );
    });

    test('the installed resolver is used as-is', () {
      final level = FakeLevel();
      final state = SableCommandState(levelOf: (_) => level);
      expect(state.levelOf(Object()), same(level));
    });
  });
}