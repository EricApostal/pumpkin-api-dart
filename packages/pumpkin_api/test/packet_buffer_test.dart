import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/src/packet_buffer.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

Uint8List encode(void Function(PacketWriter w) write) =>
    PacketBuffer.encode(write);

T decode<T>(List<int> data, T Function(PacketReader r) read) =>
    PacketBuffer.decode(data, read);

void main() {
  group('VarInt', () {
    // Test vectors from https://minecraft.wiki/w/Java_Edition_protocol/Data_types
    const vectors = <int, List<int>>{
      0: [0x00],
      1: [0x01],
      2: [0x02],
      127: [0x7f],
      128: [0x80, 0x01],
      255: [0xff, 0x01],
      25565: [0xdd, 0xc7, 0x01],
      2097151: [0xff, 0xff, 0x7f],
      2147483647: [0xff, 0xff, 0xff, 0xff, 0x07],
      -1: [0xff, 0xff, 0xff, 0xff, 0x0f],
      -2147483648: [0x80, 0x80, 0x80, 0x80, 0x08],
    };

    vectors.forEach((value, encoded) {
      test('$value <-> ${encoded.length} bytes', () {
        expect(encode((w) => w.writeVarInt(value)), encoded);
        expect(decode(encoded, (r) => r.readVarInt()), value);
      });
    });

    test('round trips around byte boundaries', () {
      for (final base in [0, 1 << 7, 1 << 14, 1 << 21, 1 << 28, 1 << 31]) {
        for (var d = -3; d <= 3; d++) {
          final value = (base + d).toSigned(32);
          expect(
            decode(encode((w) => w.writeVarInt(value)), (r) => r.readVarInt()),
            value,
          );
        }
      }
    });

    test('accepts non-canonical (padded) encodings like vanilla', () {
      expect(decode([0x80, 0x00], (r) => r.readVarInt()), 0);
      expect(decode([0xff, 0x80, 0x00], (r) => r.readVarInt()), 127);
    });

    test('rejects more than 5 bytes', () {
      expect(
        () =>
            decode([0x80, 0x80, 0x80, 0x80, 0x80, 0x01], (r) => r.readVarInt()),
        throwsA(isA<PacketException>()),
      );
    });

    test('rejects a fifth byte that overflows 32 bits', () {
      expect(
        () => decode([0xff, 0xff, 0xff, 0xff, 0x7f], (r) => r.readVarInt()),
        throwsA(
          isA<PacketException>().having(
            (e) => e.message,
            'message',
            contains('32 bits'),
          ),
        ),
      );
    });

    test('truncated input raises an underflow', () {
      expect(
        () => decode([0x80, 0x80], (r) => r.readVarInt()),
        throwsA(isA<PacketUnderflowException>()),
      );
      expect(
        () => decode(<int>[], (r) => r.readVarInt()),
        throwsA(isA<PacketUnderflowException>()),
      );
    });

    test('writing out of range fails', () {
      expect(() => encode((w) => w.writeVarInt(1 << 31)), throwsRangeError);
      expect(
        () => encode((w) => w.writeVarInt(-(1 << 31) - 1)),
        throwsRangeError,
      );
    });
  });

  group('VarLong', () {
    const vectors = <int, List<int>>{
      0: [0x00],
      127: [0x7f],
      128: [0x80, 0x01],
      2147483647: [0xff, 0xff, 0xff, 0xff, 0x07],
      9223372036854775807: [
        0xff,
        0xff,
        0xff,
        0xff,
        0xff,
        0xff,
        0xff,
        0xff,
        0x7f,
      ],
      -1: [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01],
      -2147483648: [0x80, 0x80, 0x80, 0x80, 0xf8, 0xff, 0xff, 0xff, 0xff, 0x01],
      -9223372036854775808: [
        0x80,
        0x80,
        0x80,
        0x80,
        0x80,
        0x80,
        0x80,
        0x80,
        0x80,
        0x01,
      ],
    };

    vectors.forEach((value, encoded) {
      test('$value <-> ${encoded.length} bytes', () {
        expect(encode((w) => w.writeVarLong(value)), encoded);
        expect(decode(encoded, (r) => r.readVarLong()), value);
      });
    });

    test('rejects more than 10 bytes', () {
      expect(
        () => decode(List.filled(11, 0x80), (r) => r.readVarLong()),
        throwsA(isA<PacketException>()),
      );
    });

    test('rejects a tenth byte that overflows 64 bits', () {
      expect(
        () => decode([...List.filled(9, 0xff), 0x02], (r) => r.readVarLong()),
        throwsA(isA<PacketException>()),
      );
    });

    test('truncated input raises an underflow', () {
      expect(
        () => decode([0xff, 0xff], (r) => r.readVarLong()),
        throwsA(isA<PacketUnderflowException>()),
      );
    });
  });

  group('fixed width numbers', () {
    test('are big endian', () {
      expect(encode((w) => w.writeShort(0x0102)), [1, 2]);
      expect(encode((w) => w.writeInt(0x01020304)), [1, 2, 3, 4]);
      expect(encode((w) => w.writeLong(0x0102030405060708)), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
    });

    test('round trip including negatives and extremes', () {
      final data = encode(
        (w) => w
          ..writeByte(-1)
          ..writeByte(200)
          ..writeBool(true)
          ..writeBool(false)
          ..writeShort(-2)
          ..writeShort(65535)
          ..writeInt(-123456789)
          ..writeInt(0xFFFFFFFF)
          ..writeLong(-9223372036854775808)
          ..writeLong(9223372036854775807)
          ..writeFloat(1.5)
          ..writeDouble(-2.25e100),
      );
      final r = PacketReader(data);
      expect(r.readByte(), -1);
      expect(r.readUnsignedByte(), 200);
      expect(r.readBool(), isTrue);
      expect(r.readBool(), isFalse);
      expect(r.readShort(), -2);
      expect(r.readUnsignedShort(), 65535);
      expect(r.readInt(), -123456789);
      expect(r.readInt(), -1);
      expect(r.readLong(), -9223372036854775808);
      expect(r.readLong(), 9223372036854775807);
      expect(r.readFloat(), 1.5);
      expect(r.readDouble(), -2.25e100);
      r.expectEnd();
    });

    test('writes reject values outside the range', () {
      expect(() => encode((w) => w.writeByte(256)), throwsRangeError);
      expect(() => encode((w) => w.writeShort(65536)), throwsRangeError);
      expect(() => encode((w) => w.writeInt(1 << 32)), throwsRangeError);
    });

    test('truncated reads report what was needed', () {
      final r = PacketReader([1, 2, 3]);
      expect(
        () => r.readInt(),
        throwsA(
          isA<PacketUnderflowException>()
              .having((e) => e.needed, 'needed', 4)
              .having((e) => e.available, 'available', 3)
              .having((e) => e.offset, 'offset', 0),
        ),
      );
      // A failed read does not consume anything.
      expect(r.position, 0);
      expect(r.readShort(), 0x0102);
    });
  });

  group('String', () {
    test('is length prefixed UTF-8', () {
      expect(encode((w) => w.writeString('hi')), [2, 0x68, 0x69]);
      expect(encode((w) => w.writeString('')), [0]);
      expect(decode([2, 0x68, 0x69], (r) => r.readString()), 'hi');
    });

    test('round trips multi-byte UTF-8', () {
      for (final text in ['é', '日本語', 'a😀b', '\u{10FFFF}', 'mixed ü 😀 日']) {
        final data = encode((w) => w.writeString(text));
        expect(decode(data, (r) => r.readString()), text);
        // The prefix counts bytes, not characters.
        expect(data[0], utf8.encode(text).length);
      }
    });

    test('maximum length counts UTF-16 code units', () {
      // An emoji is 2 code units, 4 bytes.
      expect(
        () => encode((w) => w.writeString('😀😀', maxLength: 3)),
        throwsA(isA<PacketException>()),
      );
      expect(encode((w) => w.writeString('😀', maxLength: 2)), hasLength(5));
      final data = encode((w) => w.writeString('😀😀'));
      expect(
        () => decode(data, (r) => r.readString(maxLength: 3)),
        throwsA(isA<PacketException>()),
      );
      expect(decode(data, (r) => r.readString(maxLength: 4)), '😀😀');
    });

    test('rejects a length above 3 bytes per character before reading', () {
      final data = encode((w) => w.writeVarInt(31));
      expect(
        () => decode(data, (r) => r.readString(maxLength: 10)),
        throwsA(
          isA<PacketException>().having(
            (e) => e.message,
            'message',
            contains('longer than the maximum'),
          ),
        ),
      );
    });

    test('default maximum is 32767 characters', () {
      final ok = 'a' * 32767;
      expect(
        decode(encode((w) => w.writeString(ok)), (r) => r.readString()),
        ok,
      );
      expect(
        () => encode((w) => w.writeString('a' * 32768)),
        throwsA(isA<PacketException>()),
      );
    });

    test('negative length is rejected', () {
      expect(
        () => decode([0xff, 0xff, 0xff, 0xff, 0x0f], (r) => r.readString()),
        throwsA(isA<PacketException>()),
      );
    });

    test('truncated string raises an underflow', () {
      expect(
        () => decode([5, 0x68, 0x69], (r) => r.readString()),
        throwsA(isA<PacketUnderflowException>()),
      );
    });

    test('invalid UTF-8 is rejected', () {
      expect(
        () => decode([2, 0xc3, 0x28], (r) => r.readString()),
        throwsA(
          isA<PacketException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    });
  });

  group('UUID', () {
    const text = '00112233-4455-6677-8899-aabbccddeeff';

    test('is two big endian longs', () {
      expect(encode((w) => w.writeUuid(text)), [
        0x00,
        0x11,
        0x22,
        0x33,
        0x44,
        0x55,
        0x66,
        0x77,
        0x88,
        0x99,
        0xaa,
        0xbb,
        0xcc,
        0xdd,
        0xee,
        0xff,
      ]);
    });

    test('round trips and accepts text without dashes', () {
      expect(
        decode(encode((w) => w.writeUuid(text)), (r) => r.readUuid()),
        text,
      );
      expect(
        decode(
          encode((w) => w.writeUuid('00112233445566778899AABBCCDDEEFF')),
          (r) => r.readUuid(),
        ),
        text,
      );
      const nil = '00000000-0000-0000-0000-000000000000';
      expect(decode(encode((w) => w.writeUuid(nil)), (r) => r.readUuid()), nil);
      const max = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
      expect(decode(encode((w) => w.writeUuid(max)), (r) => r.readUuid()), max);
    });

    test('rejects invalid text', () {
      for (final bad in [
        '',
        'nope',
        '0011223-4455-6677-8899-aabbccddeeff',
        'g0112233-4455-6677-8899-aabbccddeeff',
        '${text}00',
      ]) {
        expect(
          () => encode((w) => w.writeUuid(bad)),
          throwsA(isA<PacketException>()),
          reason: bad,
        );
      }
    });

    test('truncated input raises an underflow', () {
      expect(
        () => decode(List.filled(15, 0), (r) => r.readUuid()),
        throwsA(isA<PacketUnderflowException>()),
      );
    });
  });

  group('byte array', () {
    test('is length prefixed', () {
      expect(encode((w) => w.writeByteArray([9, 8, 7])), [3, 9, 8, 7]);
      expect(decode([3, 9, 8, 7], (r) => r.readByteArray()), [9, 8, 7]);
      expect(decode([0], (r) => r.readByteArray()), isEmpty);
    });

    test('maximum length is enforced both ways', () {
      expect(
        () => encode((w) => w.writeByteArray([1, 2, 3], maxLength: 2)),
        throwsA(isA<PacketException>()),
      );
      expect(
        () => decode([3, 1, 2, 3], (r) => r.readByteArray(maxLength: 2)),
        throwsA(isA<PacketException>()),
      );
    });

    test('a length beyond the data raises an underflow without allocating', () {
      expect(
        () =>
            decode([0xff, 0xff, 0xff, 0xff, 0x07, 1], (r) => r.readByteArray()),
        throwsA(isA<PacketUnderflowException>()),
      );
    });

    test('readBytes copies', () {
      final source = bytes([1, 2, 3]);
      final reader = PacketReader(source);
      final copy = reader.readBytes(3);
      source[0] = 99;
      expect(copy, [1, 2, 3]);
    });
  });

  group('block position', () {
    test('matches the documented packing', () {
      // Packed with the documented formula for (18357644, 831, -20882616),
      // the example in the protocol documentation.
      const packed = 0x4607632C15B4833F;
      final data = encode((w) => w.writeLong(packed));
      expect(decode(data, (r) => r.readBlockPos()), (18357644, 831, -20882616));
      expect(encode((w) => w.writeBlockPos((18357644, 831, -20882616))), data);
    });

    test('round trips extremes and negatives', () {
      for (final pos in [
        (0, 0, 0),
        (-1, -1, -1),
        (0x1FFFFFF, 0x7FF, 0x1FFFFFF),
        (-0x2000000, -0x800, -0x2000000),
        (100, 64, -100),
      ]) {
        expect(
          decode(encode((w) => w.writeBlockPos(pos)), (r) => r.readBlockPos()),
          pos,
        );
      }
    });

    test('packs x high, z middle, y low', () {
      expect(
        decode(encode((w) => w.writeBlockPos((1, 2, 3))), (r) => r.readLong()),
        (1 << 38) | (3 << 12) | 2,
      );
    });

    test('rejects coordinates that do not fit', () {
      expect(
        () => encode((w) => w.writeBlockPos((0x2000000, 0, 0))),
        throwsRangeError,
      );
      expect(
        () => encode((w) => w.writeBlockPos((0, 0x800, 0))),
        throwsRangeError,
      );
      expect(
        () => encode((w) => w.writeBlockPos((0, 0, -0x2000001))),
        throwsRangeError,
      );
    });
  });

  group('optional and list', () {
    test('optional', () {
      expect(
        encode((w) => w.writeOptional<int>(null, (w, v) => w.writeVarInt(v))),
        [0],
      );
      expect(
        encode((w) => w.writeOptional<int>(5, (w, v) => w.writeVarInt(v))),
        [1, 5],
      );
      expect(decode([0], (r) => r.readOptional((r) => r.readVarInt())), isNull);
      expect(decode([1, 5], (r) => r.readOptional((r) => r.readVarInt())), 5);
    });

    test('list', () {
      final data = encode(
        (w) => w.writeList<String>(['a', 'bc'], (w, s) => w.writeString(s)),
      );
      expect(data, [2, 1, 0x61, 2, 0x62, 0x63]);
      expect(decode(data, (r) => r.readList((r) => r.readString())), [
        'a',
        'bc',
      ]);
      expect(decode([0], (r) => r.readList((r) => r.readString())), isEmpty);
    });

    test('list limits its size', () {
      expect(
        () => decode([
          3,
          1,
          1,
          1,
        ], (r) => r.readList((r) => r.readByte(), maxLength: 2)),
        throwsA(isA<PacketException>()),
      );
      expect(
        () => decode([
          0xff,
          0xff,
          0xff,
          0xff,
          0x0f,
        ], (r) => r.readList((r) => r.readByte())),
        throwsA(isA<PacketException>()),
      );
    });

    test('list with a truncated element raises an underflow', () {
      expect(
        () => decode([2, 1], (r) => r.readList((r) => r.readByte())),
        throwsA(isA<PacketUnderflowException>()),
      );
    });
  });

  group('PacketReader', () {
    test('tracks position and remaining', () {
      final r = PacketReader([1, 2, 3, 4]);
      expect(r.remaining, 4);
      r.skip(1);
      expect(r.position, 1);
      expect(r.readRemainingBytes(), [2, 3, 4]);
      expect(r.isExhausted, isTrue);
      r.expectEnd();
    });

    test('expectEnd rejects trailing bytes', () {
      final r = PacketReader([1, 2]);
      r.readByte();
      expect(() => r.expectEnd(), throwsA(isA<PacketException>()));
    });

    test('accepts plain lists', () {
      expect(PacketReader(<int>[7]).readByte(), 7);
    });

    test('skip past the end raises an underflow', () {
      expect(
        () => PacketReader([1]).skip(2),
        throwsA(isA<PacketUnderflowException>()),
      );
    });
  });

  group('PacketBuffer.decode', () {
    test('rejects trailing data unless allowed', () {
      expect(
        () => PacketBuffer.decode([1, 2], (r) => r.readByte()),
        throwsA(isA<PacketException>()),
      );
      expect(
        PacketBuffer.decode([1, 2], (r) => r.readByte(), allowTrailing: true),
        1,
      );
    });
  });

  group('PayloadCodec', () {
    final codec = PayloadCodec<(int, String)>.buffer(
      write: (w, v) => w
        ..writeVarInt(v.$1)
        ..writeString(v.$2),
      read: (r) => (r.readVarInt(), r.readString()),
    );

    test('buffer codec round trips', () {
      final data = codec.encode((300, 'héllo'));
      expect(codec.decode(data), (300, 'héllo'));
      expect(codec.decode(data.toList()), (300, 'héllo'));
    });

    test('buffer codec rejects trailing data by default', () {
      final data = [...codec.encode((1, 'x')), 0];
      expect(() => codec.decode(data), throwsA(isA<PacketException>()));
      final lenient = PayloadCodec<int>.buffer(
        write: (w, v) => w.writeVarInt(v),
        read: (r) => r.readVarInt(),
        requireEnd: false,
      );
      expect(lenient.decode([5, 9, 9]), 5);
    });

    test('buffer codec rejects truncated data', () {
      expect(
        () => codec.decode(<int>[0xac]),
        throwsA(isA<PacketUnderflowException>()),
      );
    });

    test('function codec', () {
      final c = PayloadCodec<int>.of(
        encode: (v) => bytes([v]),
        decode: (d) => d.single,
      );
      expect(c.decode(c.encode(42)), 42);
    });

    test('ready-made codecs', () {
      expect(PayloadCodecs.bytes.decode(bytes([1, 2])), [1, 2]);
      expect(PayloadCodecs.utf8Text.encode('hé'), utf8.encode('hé'));
      expect(PayloadCodecs.utf8Text.decode(utf8.encode('hé')), 'hé');
      expect(
        PayloadCodecs.string.decode(PayloadCodecs.string.encode('x')),
        'x',
      );
      expect(
        PayloadCodecs.json.decode(
          PayloadCodecs.json.encode({
            'a': [1, 2],
          }),
        ),
        {
          'a': [1, 2],
        },
      );
      expect(
        () => PayloadCodecs.json.decode(utf8.encode('{')),
        throwsFormatException,
      );
    });
  });

  group('channel lists', () {
    test('round trip and wire format', () {
      final bytes = encodeChannelList(['a:b', 'mod:ping']);
      expect(bytes, [...'a:b'.codeUnits, 0, ...'mod:ping'.codeUnits, 0]);
      expect(decodeChannelList(bytes), ['a:b', 'mod:ping']);
      expect(decodeChannelList(const []), isEmpty);
    });
  });
}
