// The storage payload codec: gzip NBT, the format Sable's Java mod writes.
//
// Java writes every `.slvls`/`.slvlr` payload with
// `NbtIo.writeCompressed`/`readCompressed` (`SubLevelStorageFile.java:29,316-348`),
// which is a gzip stream around an unnamed NBT compound. The port has no
// `dart:io` (it is a wasm component) and the plugin API exposes no compression,
// so the codec carries its own gzip. These tests cross-check both directions
// against `dart:io`'s `GZipCodec` — the same zlib the JVM's
// `GZIPInputStream`/`GZIPOutputStream` wraps — so "a Java payload decodes" and
// "Java can read what the port writes" are actually exercised, not assumed.
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:sable/sable.dart';
import 'package:test/test.dart';

Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

Uint8List pseudoRandom(int length, int seed) {
  final out = Uint8List(length);
  var state = seed;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = (state >> 16) & 0xFF;
  }
  return out;
}

void main() {
  group('gzip', () {
    test('round trips through the port\'s own codec', () {
      for (final length in [0, 1, 100, 0xFFFF, 0x10000, 300000]) {
        final payload = pseudoRandom(length, length + 1);
        expect(gzipDecode(gzipEncode(payload)), payload, reason: 'length $length');
      }
    });

    test('a payload the port writes is read by zlib (what Java uses)', () {
      for (final length in [0, 1, 100, 0xFFFF, 0x10000, 200000]) {
        final payload = pseudoRandom(length, length + 7);
        expect(gzip.decode(gzipEncode(payload)), payload, reason: 'length $length');
      }
    });

    test('a payload compressed by zlib is read by the port', () {
      // Compressible data, so zlib picks fixed/dynamic Huffman codes rather
      // than stored blocks, and a large one so it uses back-references.
      final repeating = Uint8List.fromList(List<int>.generate(400000, (i) => i % 251));
      final mixed = Uint8List.fromList([...pseudoRandom(50000, 3), ...repeating]);
      for (final payload in [bytesOf([]), bytesOf([1, 2, 3]), repeating, mixed]) {
        final compressed = Uint8List.fromList(gzip.encode(payload));
        expect(gzipDecode(compressed), payload, reason: 'length ${payload.length}');
      }
    });

    test('rejects a truncated stream and a corrupt payload', () {
      final compressed = Uint8List.fromList(gzip.encode(pseudoRandom(5000, 11)));
      expect(
        () => gzipDecode(Uint8List.sublistView(compressed, 0, compressed.length ~/ 2)),
        throwsFormatException,
      );

      final corrupt = Uint8List.fromList(compressed);
      corrupt[corrupt.length - 6] ^= 0xFF; // inside the deflate data
      expect(() => gzipDecode(corrupt), throwsFormatException);

      expect(() => gzipDecode(bytesOf([1, 2, 3])), throwsFormatException);
    });
  });

  group('NBT layout', () {
    test('writes the unnamed root compound Java writes', () {
      final tag = <String, Object?>{'a': 1, 'b': 'x'};
      expect(
        writeNbt(tag),
        bytesOf([
          10, // TAG_Compound root
          0, 0, // unnamed
          3, 0, 1, 0x61, 0, 0, 0, 1, // int "a" = 1
          8, 0, 1, 0x62, 0, 1, 0x78, // string "b" = "x"
          0, // TAG_End
        ]),
      );
      expect(readNbt(writeNbt(tag)), {'a': 1, 'b': 'x'});
    });

    test('keeps the Java tag types of a Sable payload', () {
      final uuid = [1, 2, 3, 4];
      final occupancy = <int>[0x8000000000000001, 2];
      final tag = <String, Object?>{
        'uuid': uuid,
        'plot': {'plot_x': 3, 'log_size': 7, 'biome': 'minecraft:plains'},
        'pose': {'position': {'x': 1.5, 'y': -2.5, 'z': 3.5}},
        'world_bounds': {'minX': 0.0, 'maxX': 16.0},
        'loading_dependencies': [uuid],
        'sub_level_occupancy': occupancy,
        'flag': true,
        'raw': Uint8List.fromList([9, 8]),
      };
      final decoded = readNbt(writeNbt(tag));

      expect(decoded['uuid'], uuid, reason: 'an int array stays an int array');
      expect(decoded['sub_level_occupancy'], occupancy, reason: 'a long array keeps 64 bits');
      expect(decoded['flag'], 1, reason: 'a bool is a byte');
      expect(decoded['raw'], [9, 8], reason: 'a byte array stays a byte array');
      expect((decoded['loading_dependencies']! as List).first, uuid);
      expect(decoded['plot'], {'plot_x': 3, 'log_size': 7, 'biome': 'minecraft:plains'});

      // Re-encoding the decoded tag must keep the Java tag types of every key
      // whose type Java's readers are strict about: int arrays, long arrays,
      // doubles, strings and nested compounds. The one exception is a bare byte
      // (`flag` above): NBT has no byte *value* in Dart, so it decodes to an int
      // and re-encodes as an int. In a Sable payload the only such key is the
      // plot's `isLightOn`, which Java's own `ServerLevelPlot.save` writes on the
      // plot tag instead of the chunk tag (a quirk of the mod), and which the
      // port never produces.
      final reEncoded = readNbt(writeNbt(decoded));
      expect(reEncoded['uuid'], uuid);
      expect(reEncoded['sub_level_occupancy'], occupancy);
      expect(reEncoded['flag'], 1);
      expect(reEncoded['raw'], [9, 8]);
      expect(reEncoded['plot'], decoded['plot']);
      expect(reEncoded['pose'], decoded['pose']);
      expect(reEncoded['world_bounds'], decoded['world_bounds']);
      expect((reEncoded['loading_dependencies']! as List).first, uuid);
    });

    test('rejects a truncated tag', () {
      final full = writeNbt(<String, Object?>{'a': 1});
      expect(
        () => readNbt(Uint8List.sublistView(full, 0, full.length - 2)),
        throwsFormatException,
      );
    });
  });

  group('SubLevelCodec', () {
    final codec = NbtSubLevelCodec();

    test('round trips a tag through the codec', () {
      final tag = <String, Object?>{'uuid': [1, 2, 3, 4], 'pose': {'x': 0.0}};
      expect(codec.decode(codec.encode(tag)), tag);
    });

    test('decodes what the JVM would write: gzip NBT', () {
      final payload = gzip.encode(writeNbt(<String, Object?>{'uuid': [1, 2, 3, 4]}));
      expect(codec.decode(Uint8List.fromList(payload)), {'uuid': [1, 2, 3, 4]});
    });

    test('reads uncompressed NBT when the compression flag is off', () {
      final plain = NbtSubLevelCodec(compress: false);
      final bytes = writeNbt(<String, Object?>{'uuid': [1, 2, 3, 4]});
      expect(plain.decode(bytes), {'uuid': [1, 2, 3, 4]});
      // ... and still reads a compressed payload, since the magic is checked.
      expect(plain.decode(gzipEncode(bytes)), {'uuid': [1, 2, 3, 4]});
    });

    test('a JSON payload fails loudly instead of decoding to nothing', () {
      const json = JsonSubLevelCodec();
      final jsonBytes = json.encode({'uuid': [1, 2, 3, 4]});
      expect(() => codec.decode(jsonBytes), throwsFormatException);
    });
  });
}