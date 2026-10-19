import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:create/src/data/datapack.g.dart';
import 'package:create/src/data/datapack_install.dart';
import 'package:create/src/data/datapack_settings.dart';
import 'package:create/src/data/pack_format.dart';
import 'package:test/test.dart';

final class _MemorySink implements PackSink {
  final Map<String, List<int>> files = {};
  final Set<String> dirs = {};

  @override
  bool exists(String path) => files.containsKey(path) || dirs.contains(path) || files.keys.any((k) => k.startsWith('$path/'));

  @override
  String readString(String path) => utf8.decode(files[path]!);

  @override
  void writeBytes(String path, List<int> bytes) => files[path] = bytes;

  @override
  void writeString(String path, String text) => files[path] = utf8.encode(text);

  @override
  void createDirectory(String path) => dirs.add(path);

  @override
  void deleteRecursive(String path) {
    files.removeWhere((k, _) => k == path || k.startsWith('$path/'));
    dirs.removeWhere((k) => k == path || k.startsWith('$path/'));
  }
}

void main() {
  group('pack format', () {
    test('entries round trip through gzip, base64 and chunks', () {
      final random = Random(7);
      final files = [
        PackFile('data/create/recipe/a.json', Uint8List.fromList(utf8.encode('{"type":"minecraft:smelting"}'))),
        PackFile('data/create/empty.json', Uint8List(0)),
        PackFile('data/create/structure/ü.nbt', Uint8List.fromList(List.generate(70000, (_) => random.nextInt(256)))),
        PackFile('data/c/tags/x.json', Uint8List.fromList(utf8.encode('abc' * 5000))),
      ];
      final raw = encodePackEntries(files);
      final gz = Uint8List.fromList(gzip.encode(raw));
      final chunks = chunkString(base64Encode(gz), size: 100);
      expect(chunks.length, greaterThan(10));
      final back = decodePackBlob(chunks);
      expect(back.map((f) => f.path), files.map((f) => f.path));
      for (var i = 0; i < files.length; i++) {
        expect(back[i].bytes, files[i].bytes);
      }
    });

    test('gunzip handles stored, fixed and dynamic blocks', () {
      final random = Random(1);
      for (final data in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList(List.generate(200000, (_) => random.nextInt(256))), // incompressible, stored
        Uint8List.fromList(utf8.encode('hello hello hello hello' * 4000)),
        Uint8List.fromList(utf8.encode(List.generate(5000, (i) => '{"k$i":${i * 7}}').join(','))),
      ]) {
        for (final level in [1, 6, 9]) {
          expect(gunzip(Uint8List.fromList(GZipCodec(level: level).encode(data))), data);
        }
      }
    });

    test('corrupt input throws FormatException', () {
      expect(() => gunzip(Uint8List.fromList(List.filled(40, 3))), throwsFormatException);
      final good = Uint8List.fromList(gzip.encode(utf8.encode('x' * 1000)));
      good[good.length - 5] ^= 0xff;
      expect(() => gunzip(good), throwsFormatException);
      expect(() => decodePackEntries(Uint8List.fromList([5, 65])), throwsFormatException);
    });

    test('hash depends on content and split points', () {
      expect(fnv1a64Hex([utf8.encode('ab')]), fnv1a64Hex([utf8.encode('ab')]));
      expect(fnv1a64Hex([utf8.encode('ab')]), isNot(fnv1a64Hex([utf8.encode('ac')])));
      expect(fnv1a64Hex([utf8.encode('a'), utf8.encode('b')]), isNot(fnv1a64Hex([utf8.encode('ab')])));
      expect(fnv1a64Hex([utf8.encode('ab')]), hasLength(16));
    });
  });

  group('embedded pack', () {
    test('every blob unpacks and matches its counts', () {
      expect(datapackBlobs, isNotEmpty);
      for (final blob in datapackBlobs) {
        final files = blob.unpack();
        expect(files, hasLength(blob.fileCount), reason: blob.category);
        expect(files.fold<int>(0, (n, f) => n + f.bytes.length), lessThanOrEqualTo(blob.rawBytes));
        for (final f in files.where((f) => f.path.endsWith('.json'))) {
          jsonDecode(utf8.decode(f.bytes)); // minified but valid
        }
      }
      expect(datapackBlobs.map((b) => b.category), contains('recipes'));
    });
  });

  group('installDatapack', () {
    Set<String> cats(DatapackSettings s) => s.categories;

    InstallResult run(_MemorySink sink, Set<String> categories, {String version = 'v1'}) => installDatapack(
      sink: sink,
      root: 'datapacks/create',
      version: version,
      mcmeta: datapackMcmeta,
      blobs: datapackBlobs,
      categories: categories,
    );

    test('writes once, skips when the stamp matches, rewrites on change', () {
      final sink = _MemorySink();
      final first = run(sink, cats(const DatapackSettings()));
      expect(first.wrote, isTrue);
      expect(sink.files['datapacks/create/pack.mcmeta'], isNotNull);
      expect(sink.files.keys.any((k) => k.startsWith('datapacks/create/data/create/recipe/')), isTrue);
      expect(sink.files.keys.any((k) => k.contains('/advancement/recipes/')), isFalse); // off by default
      expect(sink.dirs, contains('datapacks/create/data/create/recipe'));

      expect(run(sink, cats(const DatapackSettings())).wrote, isFalse);

      // A new version rewrites; a switched-off category disappears.
      sink.files['datapacks/create/stale.json'] = [1];
      final second = run(sink, cats(const DatapackSettings(recipes: false)), version: 'v2');
      expect(second.wrote, isTrue);
      expect(sink.files.containsKey('datapacks/create/stale.json'), isFalse);
      expect(sink.files.keys.any((k) => k.startsWith('datapacks/create/data/create/recipe/')), isFalse);
      expect(sink.files.keys.any((k) => k.startsWith('datapacks/create/data/create/loot_table/')), isTrue);
    });

    test('an interrupted write (no stamp) is redone', () {
      final sink = _MemorySink();
      run(sink, cats(const DatapackSettings()));
      sink.files.remove('datapacks/create/.stamp');
      expect(run(sink, cats(const DatapackSettings())).wrote, isTrue);
    });
  });

  group('DatapackSettings', () {
    test('defaults and mapping', () {
      final s = DatapackSettingsMapper.fromMap({'recipe_advancements': true, 'loot_tables': false});
      expect(s.enabled, isTrue);
      expect(s.categories, containsAll(['recipes', 'recipe_advancements']));
      expect(s.categories, isNot(contains('loot_tables')));
      expect(const DatapackSettings().toMap().keys, containsAll(['enabled', 'auto_enable', 'loot_tables']));
    });
  });
}
