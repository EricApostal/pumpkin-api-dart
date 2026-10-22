// The storage-level acceptance regression: a sub-level survives a save and a
// reload.
//
// This is the layer under the live run. It exercises the whole path the Java mod
// uses — `SubLevelHoldingChunkMap.saveAll` -> region/storage files ->
// `SubLevelStorage` -> the payload codec — with the production codec
// (`NbtSubLevelCodec`, gzip NBT) and a fresh in-memory file store reopened
// afterwards, and it asserts what the live test asserts by eye: the same
// sub-level, the same pose (and its recentring), the same blocks, and the
// occupancy/ticket saved data written and read back.
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

const String uuidA = '00000000-0000-4000-8000-00000000000a';
const String uuidB = '00000000-0000-4000-8000-00000000000b';
const String folder = 'world/sublevels';

/// The sub-level's pose: a plot-grid position, so its chunk is (10000, 10000).
const double subLevelX = 160000.5;
const int chunkX = 10000;
const int chunkZ = 10000;

/// An in-memory file store.
final class MemoryFileStore implements SableFileStore {
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

/// A level with a container, a storage over [store] and its holding chunk map:
/// the four objects the plugin wires up per level.
({ServerSubLevelContainer container, FakeLevel level, FakeChunkHost chunks, SubLevelStorage storage, SubLevelHoldingChunkMap map})
    openLevel(
  MemoryFileStore store, {
  SubLevelCodec? codec,
  void Function(String, Object, StackTrace)? onError,
  bool chunksLoaded = true,
}) {
  final level = FakeLevel();
  final chunks = chunksLoaded ? FakeChunkHost(level) : _UnloadedChunkHost(level);
  final container = ServerSubLevelContainer(
    level,
    chunks,
    3,
    4,
    SubLevelContainer.defaultOrigin,
    SubLevelContainer.defaultOrigin,
  );
  SubLevelContainer.register(container);
  final storage = SubLevelStorage(store, folder, codec ?? NbtSubLevelCodec())..onError = onError;
  final map = SubLevelHoldingChunkMap(container, chunks, storage);
  container.initialize((_) => map);
  return (container: container, level: level, chunks: chunks, storage: storage, map: map);
}

/// Places [blocks] (plot-local, absolute y) in the plot's first chunk and
/// installs a real mass tracker over them, the way the physics system does.
ServerSubLevel buildSubLevel(
  ServerSubLevelContainer container,
  FakeChunkHost chunks,
  String uuid,
  Pose3d pose,
  Map<(int, int, int), String> blocks,
) {
  final subLevel = container.allocateSubLevel(uuid, 0, 0, pose) as ServerSubLevel;
  final plot = subLevel.getPlot();
  final chunk = plot.getCenterChunk();
  plot.newEmptyChunk(chunk);
  blocks.forEach((pos, state) {
    chunks.setBlock((chunk.$1 << 4) + pos.$1, pos.$2, (chunk.$2 << 4) + pos.$3, state);
  });
  // `PlotChunkHolder` caches its bounds from the scan at creation, so the
  // blocks only reach the plot bounds after a rescan.
  for (final holder in plot.getLoadedChunks()) {
    holder.buildBoundingBox();
  }
  plot.updateBoundingBox();
  subLevel.updateBoundingBox();
  subLevel.buildMassTracker();
  return subLevel;
}

void main() {
  setUp(() {
    SubLevelContainer.clearAll();
    ServerSubLevel.packetSink = null;
    ServerSubLevel.massTrackerFactory = MassTracker.build;
    ServerLevelPlot.onChunkKeyError = null;
  });

  test('a sub-level survives a save and a reload with its pose, mass and blocks', () {
    final store = MemoryFileStore();

    // ---------------------------------------------------------------- save
    // The chunk is unloaded while the level saves, which is when a sub-level
    // lives in its holding chunk (with a loaded chunk the map would pull it back
    // out during the save instead).
    final first = openLevel(store, chunksLoaded: false);
    final pose = Pose3d.full(
      Vector3d(subLevelX, 64.0, subLevelX),
      Quaterniond(0, 0.3826834, 0, 0.9238795),
      Vector3d(0, 0, 0),
      Vector3d(1, 1, 1),
    );
    // `FakeChunk` reports one 16-high section starting at y 0, so the test
    // blocks live there (the pose is independent of them).
    final subLevel = buildSubLevel(first.container, first.chunks, uuidA, pose, {
      (0, 0, 0): 'minecraft:stone',
      (1, 0, 0): 'minecraft:stone',
    });
    subLevel.setName('cart');
    expect(subLevel.getSelfMassTracker().getMass(), closeTo(2.0, 1e-9), reason: 'two 1 kg blocks');

    // A sub-level that has never been saved: the save below is what writes the
    // payload, records the pointer in the holding chunk and points the region
    // file at it.
    expect(subLevel.getLastSerializationPointer(), isNull);
    // What the payload will carry: the pose is recentred on the mass centre, so
    // the tag — not the live logical pose — is what a reload must reproduce.
    final saved = SubLevelSerializer.toData(subLevel, [uuidA]);
    final savedPosition = (saved.fullTag['pose']! as Map<String, Object?>)['position']!
        as Map<String, Object?>;
    final savedOrientation = (saved.fullTag['pose']! as Map<String, Object?>)['orientation']!
        as Map<String, Object?>;
    first.map.moveToUnloaded(subLevel, (chunkX, chunkZ));
    expect(first.container.getAllSubLevels(), isEmpty, reason: 'it went into the holding chunk');
    first.map.saveAll();
    first.storage.close();

    // Both files must be on disk: the region file carries the holding chunk's
    // pointers, and before this fix nothing ever wrote it — only the payload was
    // flushed at close.
    final name = SubLevelStorage.fileName(chunkX, chunkZ);
    expect(store.files.keys, contains('$folder/$name.slvlr'), reason: 'the pointer table');
    expect(store.files.keys, contains('$folder/$name.0.slvls'), reason: 'the payload file');

    // -------------------------------------------------------------- reload
    final reports = <String>[];
    final second = openLevel(store, onError: (m, e, st) => reports.add('$m: $e'));
    second.map.updateChunkStatus(chunkX, chunkZ, true);
    second.map.processChanges();
    expect(reports, isEmpty, reason: 'the reload must not have to report anything');

    final reloaded = second.container.getAllSubLevels().whereType<ServerSubLevel>().toList();
    expect(reloaded, hasLength(1), reason: 'the sub-level must come back from disk');
    final back = reloaded.single;
    expect(back.uniqueId, uuidA);
    expect(back.name, 'cart');
    // The pose came back exactly as it was saved, including the recentring.
    expect(back.logicalPose.position().x, closeTo(savedPosition['x']! as double, 1e-9));
    expect(back.logicalPose.position().y, closeTo(savedPosition['y']! as double, 1e-9));
    expect(back.logicalPose.position().z, closeTo(savedPosition['z']! as double, 1e-9));
    expect(back.logicalPose.orientation().x, closeTo(savedOrientation['x']! as double, 1e-9));
    expect(back.logicalPose.orientation().y, closeTo(savedOrientation['y']! as double, 1e-9),
        reason: 'the orientation survives the round trip');
    expect(back.logicalPose.orientation().w, closeTo(savedOrientation['w']! as double, 1e-9));
    expect(savedOrientation['y']! as double, closeTo(0.3826834, 1e-9));
    expect(back.getLastSerializationPointer(), isNotNull, reason: 'a reloaded sub-level keeps its pointer');

    // The blocks of the plot came back, and so did the mass-bearing bounds.
    final plot = back.getPlot();
    final center = plot.getCenterChunk();
    final chunk = second.chunks.getLoadedChunk(center.$1, center.$2) as FakeChunk?;
    expect(chunk, isNotNull, reason: 'the plot chunk was restored');
    expect(chunk!.blocks[(0, 0, 0)], 'minecraft:stone');
    expect(chunk.blocks[(1, 0, 0)], 'minecraft:stone');
    expect(plot.getBoundingBox().volume(), greaterThan(0));
  });

  test('the saved pose is recentred on the centre of mass', () {
    final opened = openLevel(MemoryFileStore());
    final subLevel = buildSubLevel(opened.container, opened.chunks, uuidA, Pose3d(), {
      (0, 0, 0): 'minecraft:stone',
      (2, 0, 0): 'minecraft:stone',
    });

    // The tracker works in the plot grid's world coordinates; the two blocks sit
    // two blocks apart, so the mass centre is between them.
    final center = subLevel.getSelfMassTracker().getCenterOfMass();
    expect(center.x, greaterThan(0.0));
    expect(subLevel.getSelfMassTracker().getMass(), closeTo(2.0, 1e-9));

    final data = SubLevelSerializer.toData(subLevel, []);
    final poseTag = data.fullTag['pose']! as Map<String, Object?>;
    final position = poseTag['position']! as Map<String, Object?>;
    final rotationPoint = poseTag['rotation_point']! as Map<String, Object?>;
    expect(position['x'], closeTo(center.x, 1e-9), reason: 'Java recentres the saved pose on the mass');
    expect(position['x'], isNot(0.0), reason: 'the recentring actually moved the pose');
    expect(rotationPoint['x'], closeTo(center.x, 1e-9));
  });

  test('the occupancy and ticket saved data round trip through their files', () {
    final store = MemoryFileStore();
    final files = SavedDataFiles(store: store, folder: '$folder/data', codec: NbtSubLevelCodec());

    final occupancy = BitGrid(64)..set(3)..set(63);
    files.write(occupancySavedDataName, OccupancySavedData.save(occupancy));
    final info = SubLevelTicketInfo(
      const GlobalSavedSubLevelPointer(9, -9, 1, 1023),
      {
        SubLevelLoadingTicket<Object?>(
          SubLevelLoadingTicketType.commandForced,
          uuidA,
          null,
        ),
      },
    );
    files.write(ticketsSavedDataName, TicketsSavedData.save({uuidA: info}));

    // Both files are gzip NBT, like the Java `SavedDataStorage` writes.
    for (final name in [occupancySavedDataName, ticketsSavedDataName]) {
      expect(store.files['$folder/data/$name.dat'], isNotNull);
      expect(store.files['$folder/data/$name.dat']!.sublist(0, 2), [0x1f, 0x8b]);
    }

    final restoredOccupancy = BitGrid(64);
    OccupancySavedData.load(files.read(occupancySavedDataName)!, restoredOccupancy);
    expect(restoredOccupancy.get(3), isTrue);
    expect(restoredOccupancy.get(63), isTrue);

    final restoredTickets = TicketsSavedData.load(files.read(ticketsSavedDataName)!);
    expect(restoredTickets[uuidA]!.pointer, const GlobalSavedSubLevelPointer(9, -9, 1, 1023));
  });

  test('the occupancy is marked dirty when a plot is allocated, the tickets on a save', () {
    final store = MemoryFileStore();
    final opened = openLevel(store);
    final marks = <String>[];
    opened.container.hostOrNull = _RecordingHost()..onMark = marks.add;

    // `SubLevelContainer.java:258-260`: allocating a plot changes the occupancy
    // bitmap, so the saved data must be rewritten — without this a restart
    // reloads an empty grid and the next assembly can be given a plot index a
    // stored sub-level still owns.
    buildSubLevel(opened.container, opened.chunks, uuidA, Pose3d(), {(0, 0, 0): 'minecraft:stone'});
    expect(marks, contains(occupancySavedDataName));

    // `SubLevelHoldingChunkMap.java:331`: and the tickets are marked on a save.
    marks.clear();
    opened.map.saveAll();
    expect(marks, contains(ticketsSavedDataName));
  });

  group('loud failures', () {
    /// A payload written by the port before the codec was fixed.
    MemoryFileStore portWrittenWorld() {
      final store = MemoryFileStore();
      final legacy = openLevel(store, codec: const JsonSubLevelCodec());
      legacy.storage.attemptSaveSubLevel(
        chunkX,
        chunkZ,
        SubLevelData(
          uuidA,
          BoundingBox3d.full(0, 0, 0, 1, 1, 1),
          Pose3d(),
          const [],
          {'uuid': uuidA},
        ),
      );
      legacy.storage.close();
      return store;
    }

    test('a payload the codec cannot read is reported, not swallowed', () {
      final reports = <String>[];
      final opened = openLevel(portWrittenWorld(), onError: (message, error, stack) => reports.add('$message: $error'));
      final data = opened.storage.attemptLoadSubLevel(chunkX, chunkZ, const SavedSubLevelPointer(0, 0));

      expect(data, isNull, reason: 'a payload the codec cannot read is not a sub-level');
      expect(reports, hasLength(1), reason: 'and it must be reported');
      expect(reports.single, contains('Failed to load sub-level'));
      expect(reports.single, contains('did not decode with this file\'s codec'));
    });

    test('without a sink the failure is thrown instead of dropped', () {
      final opened = openLevel(portWrittenWorld());
      expect(
        () => opened.storage.attemptLoadSubLevel(chunkX, chunkZ, const SavedSubLevelPointer(0, 0)),
        throwsA(
          isA<SubLevelStorageFailure>()
              .having((failure) => failure.message, 'message', contains('Failed to load sub-level'))
              .having((failure) => failure.cause, 'cause', isA<SubLevelPayloadException>()),
        ),
      );
    });

    test('an absent holding chunk is not a failure', () {
      final reports = <String>[];
      final opened = openLevel(MemoryFileStore(), onError: (message, error, stack) => reports.add(message));
      expect(opened.storage.attemptLoadHoldingChunk(4, 4), isNull);
      expect(reports, isEmpty, reason: 'an empty slot is not an error');
    });
  });

  group('plot chunk keys', () {
    test('a plot saves its chunks under the packed ChunkPos key Java writes', () {
      final opened = openLevel(MemoryFileStore());
      final subLevel = buildSubLevel(opened.container, opened.chunks, uuidA, Pose3d(), {
        (0, 0, 0): 'minecraft:stone',
      });

      final tag = subLevel.getPlot().save();
      final chunks = tag['chunks']! as Map<String, Object?>;
      final local = subLevel.getPlot().toLocal(subLevel.getPlot().getCenterChunk());
      expect(chunks.keys, contains('${SableBufferUtils.packChunk(local.$1, local.$2)}'));
      expect(chunks.keys.any((key) => key.contains(',')), isFalse, reason: 'not the old "x,z" form');
    });

    test('a Java key and the port\'s old key both load a chunk, an unreadable one is reported', () {
      final opened = openLevel(MemoryFileStore());
      final subLevel = buildSubLevel(opened.container, opened.chunks, uuidA, Pose3d(), {
        (0, 0, 0): 'minecraft:stone',
      });
      final plot = subLevel.getPlot();
      final center = plot.getCenterChunk();
      final local = plot.toLocal(center);

      final javaKey = '${SableBufferUtils.packChunk(local.$1, local.$2)}';
      final legacyKey = '${local.$1},${local.$2}';
      expect(javaKey, isNot(legacyKey));

      final reported = <String>[];
      ServerLevelPlot.onChunkKeyError = reported.add;

      for (final key in [javaKey, legacyKey]) {
        plot.load({
          'plot_x': 0,
          'plot_z': 0,
          'log_size': 4,
          'data_version': 1,
          'biome': 'minecraft:plains',
          'chunks': {key: opened.chunks.serializeChunk(opened.chunks.createEmptyChunk(center.$1, center.$2))},
        });
        expect(plot.getLoadedChunks().map((holder) => holder.pos), contains(center), reason: 'key $key');
        plot.onRemove();
      }
      expect(reported, isEmpty);

      plot.load({
        'plot_x': 0,
        'plot_z': 0,
        'log_size': 4,
        'data_version': 1,
        'chunks': {
          'not-a-position': opened.chunks.serializeChunk(opened.chunks.createEmptyChunk(center.$1, center.$2)),
        },
      });
      expect(reported, ['not-a-position']);
    });
  });
}

/// A host whose chunks never count as loaded enough: the state a sub-level is
/// in while it sits in its holding chunk.
final class _UnloadedChunkHost extends FakeChunkHost {
  _UnloadedChunkHost(super.level);

  @override
  bool isChunkLoadedEnough(int x, int z) => false;
}

/// A host that records what the model marks dirty, without any file access.
final class _RecordingHost implements SubLevelHost {
  void Function(String name)? onMark;

  @override
  void markSavedDataDirty(String name) => onMark?.call(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}