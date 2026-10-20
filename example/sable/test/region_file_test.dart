// Region-file round trips: the `.slvlr` chunk table and the `.slvls` sector
// store behind it.
//
// The on-disk layout is the Java one and is asserted directly:
//
//  * a 4096 byte header of 1024 big-endian int spans, `0xPPPPPPLL`;
//  * the header occupies whole sectors (sector 0 is always used);
//  * a payload sector starts with `int remaining` (payload length + 1) and a
//    `u8 type` (`EXTERNAL_MASK` when the payload lives in a `.slvl` file);
//  * a payload larger than 255 sectors spills to `<externalDir>/<index>.slvl`
//    and leaves a one-sector stub behind.
//
// `SubLevelRegionFile` is a 32x32 table: `index = localX | (localZ << 5)`.
//
// Transcribed from `SubLevelStorageFile` / `SubLevelRegionFile` on
// `port/26.3`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

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

const String regionPath = 'world/sublevels/r.0.0.slvlr';
const String externalDir = 'world/sublevels/external';
const SubLevelCodec codec = JsonSubLevelCodec();

SubLevelRegionFile openRegion(MemoryFileStore store) =>
    SubLevelRegionFile.open(store, regionPath, externalDir, codec);

int headerInt(MemoryFileStore store, int index, [String path = regionPath]) =>
    ByteData.sublistView(store.files[path]!, index * 4, index * 4 + 4).getInt32(0);

void main() {
  late MemoryFileStore store;
  late SubLevelRegionFile region;

  setUp(() {
    store = MemoryFileStore();
    region = openRegion(store);
  });

  group('index layout', () {
    test('a region is 32x32 chunks and the index is x | z << 5', () {
      expect(SubLevelRegionFile.sideLength, 32);
      expect(SubLevelRegionFile.logSideLength, 5);
      expect(SubLevelRegionFile.sectorSize, 128);

      expect(region.getIndex(0, 0), 0);
      expect(region.getIndex(31, 0), 31);
      expect(region.getIndex(0, 1), 32);
      expect(region.getIndex(5, 7), 5 | (7 << 5));
      expect(region.getIndex(31, 31), 1023);
    });

    test('reading outside the region wraps to its local chunk', () {
      region.trySave(3, 4, {'marker': 'here'});
      region.flush();

      // Chunk 35 is local 3, chunk 68 is local 4.
      expect(region.read(35, 68)?['marker'], 'here');
      expect(region.read(3, 4)?['marker'], 'here');
      expect(region.read(4, 4), isNull);
    });
  });

  group('round trip', () {
    test('a holding chunk survives a flush and a reopen', () {
      region.trySave(1, 2, {
        'chunk_x': 1,
        'chunk_z': 2,
        'pointers': [
          {'storage_index': 3, 'sub_level_index': 42},
        ],
      });
      region.close();

      final reopened = openRegion(store);
      final tag = reopened.read(1, 2);
      expect(tag, isNotNull);
      expect(tag!['chunk_x'], 1);
      expect(tag['chunk_z'], 2);
      expect((tag['pointers'] as List).single['sub_level_index'], 42);
    });

    test('every one of the 1024 indices is addressable', () {
      for (var z = 0; z < 32; z++) {
        for (var x = 0; x < 32; x++) {
          region.trySave(x, z, {'at': region.getIndex(x, z)});
        }
      }
      region.close();

      final reopened = openRegion(store);
      for (var z = 0; z < 32; z++) {
        for (var x = 0; x < 32; x++) {
          expect(reopened.read(x, z)?['at'], x | (z << 5), reason: 'chunk $x,$z');
        }
      }
      expect(reopened.isEmptyFile, isFalse);
    });

    test('removing a chunk clears its index and reuses the sectors', () {
      region.trySave(0, 0, {'first': true});
      region.flush();
      final firstSpan = headerInt(store, 0);
      final firstStart = (firstSpan >> 8) & 0xFFFFFF;
      expect(firstStart, greaterThan(0));

      region.tryRemove(0, 0);
      region.flush();
      expect(headerInt(store, 0), 0);
      expect(region.read(0, 0), isNull);

      region.trySave(1, 1, {'second': true});
      region.flush();
      final secondSpan = headerInt(store, region.getIndex(1, 1));
      expect((secondSpan >> 8) & 0xFFFFFF, firstStart);
    });

    test('an empty region has an empty file', () {
      expect(region.isEmptyFile, isTrue);
      region.flush();
      expect(store.files[regionPath]!.length, 4096, reason: 'the header is one sector-aligned block');
    });
  });

  group('on-disk layout', () {
    test('the header holds one big-endian span per index', () {
      region.trySave(7, 9, {'x': 1});
      region.flush();

      final bytes = store.files[regionPath]!;
      expect(bytes.length, greaterThanOrEqualTo(4096));

      final span = headerInt(store, region.getIndex(7, 9));
      final start = (span >> 8) & 0xFFFFFF;
      final length = span & 0xFF;

      // The header occupies sectors 0..31 (4096 / 128), so data starts after.
      expect(start, greaterThanOrEqualTo(32));
      expect(length, greaterThanOrEqualTo(1));

      // The payload sector starts with `remaining = payload length + 1` and a
      // zero type byte.
      final offset = start * SubLevelRegionFile.sectorSize;
      final remaining = ByteData.sublistView(bytes, offset, offset + 4).getInt32(0);
      expect(remaining, greaterThan(1));
      expect(bytes[offset + 4], 0);
    });

    test('a payload larger than 255 sectors spills to an external file', () {
      // 255 sectors * 128 bytes - the 5 byte frame = 32635 bytes of payload.
      final big = 'x' * 40000;
      region.trySave(2, 3, {'big': big});
      region.flush();

      final span = headerInt(store, region.getIndex(2, 3));
      expect(span & 0xFF, 1, reason: 'the stub is one sector');

      final stubOffset = ((span >> 8) & 0xFFFFFF) * SubLevelRegionFile.sectorSize;
      final bytes = store.files[regionPath]!;
      expect(ByteData.sublistView(bytes, stubOffset, stubOffset + 4).getInt32(0), 1);
      expect(bytes[stubOffset + 4], 16, reason: 'EXTERNAL_MASK');

      expect(store.exists('$externalDir/${region.getIndex(2, 3)}.slvl'), isTrue);
    });

    test('an external payload survives a reopen', () {
      final big = 'y' * 40000;
      region.trySave(4, 4, {'big': big});
      region.close();

      final reopened = openRegion(store);
      expect(reopened.read(4, 4)?['big'], big);
    });

    test('overwriting an external payload with a small one drops the file', () {
      region.trySave(5, 5, {'big': 'z' * 40000});
      region.flush();
      expect(store.exists('$externalDir/${region.getIndex(5, 5)}.slvl'), isTrue);

      region.trySave(5, 5, {'small': true});
      region.flush();
      expect(store.exists('$externalDir/${region.getIndex(5, 5)}.slvl'), isFalse);
      expect(region.read(5, 5)?['small'], isTrue);
    });

    test('delete removes the file and the external payloads', () {
      region.trySave(6, 6, {'big': 'w' * 40000});
      region.flush();
      expect(store.exists(regionPath), isTrue);
      expect(store.exists('$externalDir/${region.getIndex(6, 6)}.slvl'), isTrue);

      region.delete();
      expect(store.exists(regionPath), isFalse);
      expect(store.exists('$externalDir/${region.getIndex(6, 6)}.slvl'), isFalse);
    });
  });

  group('a plain storage file', () {
    test('uses 4096 byte sectors and 1024 indices', () {
      final file = SubLevelStorageFile.open(store, 'world/sublevels/s.slvls', externalDir, codec);
      expect(file.totalIndexCapacity, 1024);
      expect(file.findFreeIndex(), 0);

      file.write(0, {'a': 1});
      file.write(1023, {'b': 2});
      file.flush();

      final reopened = SubLevelStorageFile.open(store, 'world/sublevels/s.slvls', externalDir, codec);
      expect(reopened.read(0)?['a'], 1);
      expect(reopened.read(1023)?['b'], 2);
      expect(reopened.read(1), isNull);
    });

    test('findFreeIndex skips used indices', () {
      final file = SubLevelStorageFile.open(store, 'world/sublevels/s.slvls', externalDir, codec);
      file.write(0, {'a': 1});
      file.write(1, {'a': 2});
      expect(file.findFreeIndex(), 2);

      file.clear(1);
      expect(file.findFreeIndex(), 1);
    });

    test('the payload is the codec bytes, framed in one sector', () {
      final file = SubLevelStorageFile.open(store, 'world/sublevels/s.slvls', externalDir, codec);
      final tag = {'hello': 'world'};
      file.write(0, tag);
      file.flush();

      final bytes = store.files['world/sublevels/s.slvls']!;
      final span = headerInt(store, 0, 'world/sublevels/s.slvls');
      final start = (span >> 8) & 0xFFFFFF;
      final length = span & 0xFF;
      expect(start, greaterThanOrEqualTo(1), reason: '4096 byte sectors: the header is sector 0');
      expect(length, 1);

      final payloadLength = ByteData.sublistView(bytes, start * 4096, start * 4096 + 4).getInt32(0) - 1;
      final payload = bytes.sublist(start * 4096 + 5, start * 4096 + 5 + payloadLength);
      expect(jsonDecode(utf8.decode(payload)), tag);
    });
  });
}
