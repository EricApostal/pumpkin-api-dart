// Persistence: pointers, bit grids, the sector file format, holding chunks,
// saved data and the NBT shape of poses. All pure, so this runs on the VM.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

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

void main() {
  group('saved pointers', () {
    test('pack and unpack round trip', () {
      const pointer = SavedSubLevelPointer(3, 42);
      expect(pointer.packed(), (3 << 16) | 42);
      final back = SavedSubLevelPointer.unpack(pointer.packed());
      expect(back.storageIndex, 3);
      expect(back.subLevelIndex, 42);
    });

    test('unpack sign-extends the halves like Java shorts', () {
      final packed = ((0xFFFF) << 16) | 0xFFFE;
      final pointer = SavedSubLevelPointer.unpack(packed);
      expect(pointer.storageIndex, -1);
      expect(pointer.subLevelIndex, -2);
    });

    test('global pointer map round trip', () {
      const pointer = GlobalSavedSubLevelPointer(12, -34, 1, 1023);
      final map = pointer.toMap();
      expect(map['chunk_x'], 12);
      expect(map['chunk_z'], -34);
      expect(GlobalSavedSubLevelPointer.fromMap(map), pointer);
      expect(pointer.local, const SavedSubLevelPointer(1, 1023));
    });
  });

  group('BitGrid', () {
    test('keeps the Java BitSet long-array layout', () {
      final grid = BitGrid(128);
      grid.set(0);
      grid.set(63);
      grid.set(64);
      expect(grid.toLongArray(), [(-0x8000000000000000) | 1, 1]);

      final restored = BitGrid.fromLongArray(grid.toLongArray(), 128);
      expect(restored.get(0), isTrue);
      expect(restored.get(63), isTrue);
      expect(restored.get(64), isTrue);
      expect(restored.get(1), isFalse);
    });

    test('nextClearBit skips set bits', () {
      final grid = BitGrid(8);
      grid.set(0);
      grid.set(1);
      expect(grid.nextClearBit(0), 2);
      grid.set(2);
      expect(grid.nextClearBit(0), 3);
    });

    test('an empty grid writes an empty array', () {
      expect(BitGrid(16).toLongArray(), isEmpty);
    });
  });

  group('storage file image', () {
    test('writes and reads a payload', () {
      final image = StorageFileImage(4096);
      final payload = Uint8List.fromList(List<int>.generate(100, (i) => i));
      image.write(7, payload);

      expect(image.findFreeIndex(), 0);
      expect(image.read(7), payload);
      expect(image.spanLength(image.spans[7]), 1);
    });

    test('clears an index and reuses its sectors', () {
      final image = StorageFileImage(4096);
      image.write(0, Uint8List(100));
      final start = image.spanStart(image.spans[0]);
      image.clear(0);
      expect(image.read(0), isNull);
      expect(image.usedIndices.get(0), isFalse);

      image.write(1, Uint8List(100));
      expect(image.spanStart(image.spans[1]), start);
    });

    test('spills payloads over 255 sectors to an external file', () {
      final image = StorageFileImage(4096);
      final payload = Uint8List(300 * 4096);
      image.write(2, payload);

      expect(image.externalPayloads.containsKey(2), isTrue);
      expect(image.spanLength(image.spans[2]), 1);
      expect(image.read(2)!.length, payload.length);
    });

    test('findFreeIndex returns the first unused index', () {
      final image = StorageFileImage(4096);
      image.write(0, Uint8List(10));
      image.write(2, Uint8List(10));
      expect(image.findFreeIndex(), 1);
      expect(image.totalIndexCapacity, 1024);
    });

    test('reopening a flushed image keeps the spans', () {
      final image = StorageFileImage(4096);
      image.write(5, Uint8List(20));
      final bytes = image.flushBytes();

      final reopened = StorageFileImage(4096, existing: Uint8List.fromList(bytes));
      expect(reopened.read(5)!.length, 20);
      expect(reopened.usedIndices.get(5), isTrue);
    });
  });

  group('storage file', () {
    test('round trips a tag through the file store', () {
      final store = MemoryFileStore();
      final file = SubLevelStorageFile.open(
        store,
        'sublevels/r.0.0.slvls',
        'sublevels/r.0.0.s',
        const JsonSubLevelCodec(),
      );
      file.write(3, {'uuid': [1, 2, 3, 4]});
      file.flush();

      final reopened = SubLevelStorageFile.open(
        store,
        'sublevels/r.0.0.slvls',
        'sublevels/r.0.0.s',
        const JsonSubLevelCodec(),
      );
      expect(reopened.read(3), {'uuid': [1, 2, 3, 4]});
      expect(reopened.read(4), isNull);
    });

    test('region files index chunks by local x | local z << 5', () {
      final store = MemoryFileStore();
      final region = SubLevelRegionFile.open(
        store,
        'sublevels/r.0.0.slvlr',
        'sublevels/r.0.0.r',
        const JsonSubLevelCodec(),
      );
      expect(region.getIndex(0, 0), 0);
      expect(region.getIndex(31, 0), 31);
      expect(region.getIndex(0, 1), 32);
      region.trySave(2, 3, {'pointers': [1]});
      region.flush();

      expect(region.read(2, 3), {'pointers': [1]});
      expect(region.read(3, 2), isNull);
    });
  });

  group('holding chunks', () {
    late FakeLevel level;
    late FakeChunkHost chunks;

    setUp(() {
      level = FakeLevel();
      chunks = FakeChunkHost(level);
    });

    SubLevelData data(String uuid, {List<String> dependencies = const []}) => SubLevelData(
      uuid,
      BoundingBox3d.full(0, 0, 0, 1, 1, 1),
      Pose3d(),
      dependencies,
      {'uuid': uuid},
    );

    test('pointers survive the NBT round trip', () {
      final chunk = SubLevelHoldingChunk((4, -2));
      chunk.getSubLevelPointers().add(const SavedSubLevelPointer(0, 9));
      chunk.getSubLevelPointers().add(const SavedSubLevelPointer(1, 3));

      final tag = <String, Object?>{};
      chunk.writeTo(tag);
      final restored = SubLevelHoldingChunk.from((4, -2), tag);

      expect(restored.getChunkPos(), (4, -2));
      expect(restored.getSubLevelPointers(), chunk.getSubLevelPointers());
    });

    test('snatch takes the sub-level and its dependencies', () {
      final chunk = SubLevelHoldingChunk((0, 0));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('a', dependencies: ['b']), null));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('b'), null));

      final snatched = chunk.snatch('a')!;
      expect(snatched.map((h) => h.data.uuid), ['a', 'b']);
      expect(chunk.getLoadedHoldingSubLevels(), isEmpty);
      expect(chunk.snatch('a'), isNull);
    });

    test('collectReadySubLevels waits for dependencies and loaded chunks', () {
      final chunk = SubLevelHoldingChunk((0, 0));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('a', dependencies: ['b']), null));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('b'), null));

      final ready = <String, HoldingSubLevel>{};
      chunk.collectReadySubLevels(chunks, ready);
      expect(ready.keys, unorderedEquals(['a', 'b']));
      expect(chunk.isEmpty(), isTrue);
    });

    test('an unloaded chunk blocks the ready check', () {
      final blocked = _BlockedChunkHost(level);
      final chunk = SubLevelHoldingChunk((0, 0));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('a'), null));

      final ready = <String, HoldingSubLevel>{};
      chunk.collectReadySubLevels(blocked, ready);
      expect(ready, isEmpty);
      expect(chunk.getLoadedHoldingSubLevels(), isNotEmpty);
    });

    test('a missing dependency drops the sub-level', () {
      final chunk = SubLevelHoldingChunk((0, 0));
      chunk.acceptHoldingSubLevel(HoldingSubLevel(data('a', dependencies: ['missing']), null));

      final ready = <String, HoldingSubLevel>{};
      chunk.collectReadySubLevels(chunks, ready);
      expect(ready, isEmpty);
      expect(chunk.getLoadedHoldingSubLevels(), isEmpty);
    });
  });

  group('saved data', () {
    test('occupancy round trips', () {
      final occupancy = BitGrid(64);
      occupancy.set(3);
      occupancy.set(63);
      final tag = OccupancySavedData.save(occupancy);
      expect(tag[OccupancySavedData.key], isA<List<int>>());

      final restored = BitGrid(64);
      OccupancySavedData.load(tag, restored);
      expect(restored.get(3), isTrue);
      expect(restored.get(63), isTrue);
      expect(restored.get(4), isFalse);
    });

    test('tickets round trip with the command-forced type', () {
      final info = SubLevelTicketInfo(
        const GlobalSavedSubLevelPointer(1, 2, 3, 4),
        {
          SubLevelLoadingTicket<Object?>(
            SubLevelLoadingTicketType.commandForced,
            '00000000-0000-4000-8000-000000000001',
            null,
          ),
        },
      );
      final tag = TicketsSavedData.save({
        '00000000-0000-4000-8000-000000000001': info,
      });

      final restored = TicketsSavedData.load(tag);
      final loaded = restored['00000000-0000-4000-8000-000000000001']!;
      expect(loaded.pointer, const GlobalSavedSubLevelPointer(1, 2, 3, 4));
      expect(loaded.tickets.length, 1);
      expect(loaded.tickets.first.type, SubLevelLoadingTicketType.commandForced);
    });

    test('a ticket without a pointer is still saved', () {
      const uuid = '00000000-0000-4000-8000-000000000002';
      final tag = TicketsSavedData.save({
        uuid: SubLevelTicketInfo(null, {
          SubLevelLoadingTicket<Object?>(
            SubLevelLoadingTicketType.commandForced,
            uuid,
            null,
          ),
        }),
      });
      expect(TicketsSavedData.load(tag)[uuid]!.pointer, isNull);
    });
  });

  group('NBT helpers', () {
    test('pose round trip keeps position, orientation and rotation point', () {
      final pose = Pose3d.full(
        Vector3d(1.5, -2.5, 3.5),
        Quaterniond(0.1, 0.2, 0.3, 0.9)..normalize(),
        Vector3d(-1, 2, -3),
        Vector3d(1, 1, 1),
      );
      final restored = SableNbt.readPose3d(SableNbt.writePose3d(pose));

      expect(restored.position(), closeToPoseValue(1.5, -2.5, 3.5));
      expect(restored.rotationPoint(), closeToPoseValue(-1, 2, -3));
      expect(restored.scale(), closeToPoseValue(1, 1, 1));
      expect(restored.orientation().x, closeTo(0.1 / math.sqrt(0.1 * 0.1 + 0.2 * 0.2 + 0.3 * 0.3 + 0.9 * 0.9), 1e-9));
    });

    test('bounds round trip', () {
      final box = BoundingBox3d.full(1, 2, 3, 4, 5, 6);
      final restored = SableNbt.readBoundingBox(SableNbt.writeBoundingBox(box));
      expect(restored, box);
    });

    test('uuid round trips through the four-int form', () {
      const uuid = '12345678-9abc-def0-1234-56789abcdef0';
      expect(uuidFromInts(uuidToInts(uuid)), uuid);
      expect(SableNbt.readUuid(SableNbt.writeUuid(uuid)), uuid);
    });

    test('generated uuids are v4 shaped', () {
      var counter = 0;
      final uuid = randomUuidV4(() => (counter++ * 37) & 0xFF);
      expect(uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('bounded bit volume', () {
    test('index layout matches the Java formula', () {
      final volume = BoundedBitVolume3i(10, 20, 30, 11, 21, 31);
      expect(volume.getIndex(10, 20, 30), 0);
      // (localX * zSpan * ySpan) + (localZ * ySpan) + localY
      expect(volume.getIndex(10, 20, 31), 2);
      expect(volume.getIndex(10, 21, 30), 1);
      expect(volume.getIndex(11, 20, 30), 4);
      expect(volume.volume(), 8);
    });

    test('out of bounds reads are false, writes throw', () {
      final volume = BoundedBitVolume3i(0, 0, 0, 1, 1, 1);
      expect(volume.getOccupied(5, 0, 0), isFalse);
      expect(() => volume.setOccupied(5, 0, 0, true), throwsArgumentError);
    });

    test('fromBlocks builds the tight volume', () {
      final volume = BoundedBitVolume3i.fromBlocks([(0, 0, 0), (2, 3, 4)])!;
      expect(volume.getMinBlockPos(), (0, 0, 0));
      expect(volume.getMaxBlockPos(), (2, 3, 4));
      expect(volume.getOccupied(2, 3, 4), isTrue);
      expect(volume.getOccupied(1, 1, 1), isFalse);
      expect(BoundedBitVolume3i.fromBlocks(const []), isNull);
    });
  });
}

/// A host that reports every chunk as not loaded.
final class _BlockedChunkHost extends FakeChunkHost {
  _BlockedChunkHost(super.level);

  @override
  bool isChunkLoadedEnough(int x, int z) => false;
}

Matcher closeToPoseValue(double x, double y, double z) => isA<Vector3d>()
    .having((v) => v.x, 'x', closeTo(x, 1e-9))
    .having((v) => v.y, 'y', closeTo(y, 1e-9))
    .having((v) => v.z, 'z', closeTo(z, 1e-9));
