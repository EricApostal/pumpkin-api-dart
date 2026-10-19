import 'package:create/src/core/nbt.dart';
import 'package:create/src/redstone/display/config_tag.dart';
import 'package:create/src/redstone/nixie/nixie_logic.dart';
import 'package:test/test.dart';

void main() {
  group('display link source config', () {
    // The `Source` compound of the display link (`DisplayLinkBlockEntity`) is a plain
    // `CompoundTag` that is stored, sent to the client and written back unchanged. This is the
    // pure network-NBT form the configuration packet and the source GUI use; the values must
    // keep their tag types (long, float, list, compound), like Java's `CompoundTag.copy()`.
    test('round trips through network NBT with keys and types intact', () {
      final config = ConfigTag(<String, NbtValue>{
        'Id': const NbtValue.string('create:item_throughput'),
        'Interval': const NbtValue.int32(2),
        'Rate': const NbtValue.float(1.5),
        'LastReceived': const NbtValue.long(1234567890123),
        'Inactive': const NbtValue.byte(1),
        'PrevRates': NbtValue.list(const [
          NbtValue.float(-1),
          NbtValue.float(0.25),
        ]),
        'Nested': NbtValue.compound({'slot': const NbtValue.int32(3)}),
      });

      final decoded = NetworkNbt.decode(NetworkNbt.encode(config.toNbt()));
      expect(decoded, isNotNull);
      final back = ConfigTag.fromNbt(decoded);

      expect(back.keys.toSet(), config.keys.toSet());
      expect(back.getStringOr('Id', ''), 'create:item_throughput');
      expect(back.getIntOr('Interval', -1), 2);
      expect(back.getFloatOr('Rate', 0), 1.5);
      expect(back.getLongOr('LastReceived', 0), 1234567890123);
      expect(back.getBooleanOr('Inactive', false), isTrue);

      // Types are part of the parity contract: the client's `getLongOr` / `getFloatOr`
      // tolerate numbers, but the written tag must stay long / float / list / compound.
      expect(back.entries['LastReceived']!.kind, NbtKind.long);
      expect(back.entries['Rate']!.kind, NbtKind.float);
      expect(back.entries['PrevRates']!.kind, NbtKind.list);
      expect(back.entries['PrevRates']!.value, isA<List<NbtValue>>());
      expect(back.entries['Nested']!.kind, NbtKind.compound);
      expect(back.entries['Nested']!.asCompound['slot']!.value, 3);
    });

    test('an absent config reads as an empty tag', () {
      final tag = ConfigTag.fromNbt(null);
      expect(tag.isEmpty, isTrue);
      expect(tag.getStringOr('Id', 'fallback'), 'fallback');
    });

    test('a non-compound value reads as an empty tag', () {
      expect(ConfigTag.fromNbt(const NbtValue.int32(1)).isEmpty, isTrue);
      expect(ConfigTag.fromNbt(NbtValue.list(const [])).isEmpty, isTrue);
    });

    // Every scalar and array type a source config may hold must survive the network codec;
    // the display link writes the tag back unchanged, so no type may be normalised away.
    test(
      'all numeric, array and nested tags survive the network round trip',
      () {
        final config = ConfigTag(<String, NbtValue>{
          'Byte': const NbtValue.byte(7),
          'Short': const NbtValue.short(300),
          'Int': const NbtValue.int32(-5),
          'Long': const NbtValue.long(-9000000000000),
          'Float': const NbtValue.float(0.25),
          'Double': const NbtValue.double64(0.125),
          'Bytes': const NbtValue.byteArray([1, 2]),
          'Ints': const NbtValue.intArray([3, 4]),
          'Longs': const NbtValue.longArray([5, 6]),
          'List': NbtValue.list([
            NbtValue.compound({'a': const NbtValue.int32(1)}),
            NbtValue.compound({'a': const NbtValue.int32(2)}),
          ]),
          'Nested': NbtValue.compound({
            'inner': NbtValue.list([const NbtValue.string('x')]),
          }),
        });

        final back = ConfigTag.fromNbt(
          NetworkNbt.decode(NetworkNbt.encode(config.toNbt())),
        );
        expect(back.keys.toSet(), config.keys.toSet());

        expect(back.entries['Byte']!.kind, NbtKind.byte);
        expect(back.entries['Short']!.kind, NbtKind.short);
        expect(back.entries['Int']!.kind, NbtKind.int);
        expect(back.entries['Long']!.kind, NbtKind.long);
        expect(back.entries['Float']!.kind, NbtKind.float);
        expect(back.entries['Double']!.kind, NbtKind.double);
        expect(back.entries['Bytes']!.kind, NbtKind.byteArray);
        expect(back.entries['Ints']!.kind, NbtKind.intArray);
        expect(back.entries['Longs']!.kind, NbtKind.longArray);

        expect(back.entries['Byte']!.value, 7);
        expect(back.entries['Short']!.value, 300);
        expect(back.entries['Int']!.value, -5);
        expect(back.entries['Long']!.value, -9000000000000);
        expect(back.entries['Float']!.value, 0.25);
        expect(back.entries['Double']!.value, 0.125);
        expect(back.entries['Bytes']!.value, [1, 2]);
        expect(back.entries['Ints']!.value, [3, 4]);
        expect(back.entries['Longs']!.value, [5, 6]);

        final list = back.entries['List']!.value as List<NbtValue>;
        expect(list.length, 2);
        expect(list.first.asCompound['a']!.value, 1);
        expect(back.entries['Nested']!.asCompound['inner']!.kind, NbtKind.list);
        expect(
          (back.entries['Nested']!.asCompound['inner']!.value as List<NbtValue>)
              .first
              .value,
          'x',
        );
      },
    );

    test('an empty config round trips as an empty compound', () {
      final back = ConfigTag.fromNbt(
        NetworkNbt.decode(NetworkNbt.encode(ConfigTag().toNbt())),
      );
      expect(back.isEmpty, isTrue);
    });

    test('the typed accessors tolerate the numeric tags Java writes', () {
      final tag = ConfigTag(<String, NbtValue>{
        'AsLong': const NbtValue.long(3),
        'AsFloat': const NbtValue.float(2.5),
        'AsByte': const NbtValue.byte(1),
        'AsString': const NbtValue.string('7'),
      });
      expect(tag.getIntOr('AsLong', 0), 3);
      expect(tag.getIntOr('AsFloat', 0), 2);
      expect(tag.getBooleanOr('AsByte', false), isTrue);
      expect(tag.getBooleanOr('AsString', false), isFalse);
      // A string is not a number, so the fallback applies.
      expect(tag.getIntOr('AsString', -1), -1);
    });
  });

  group('nixie tube ComputerSignal', () {
    test('encodes the two 7 byte displays and decodes them back', () {
      final signal = ComputerSignal();
      signal.first
        ..r = 1
        ..g = 2
        ..b = 3
        ..blinkPeriod = 4
        ..blinkOffTime = 5
        ..glowWidth = 6
        ..glowHeight = 7;
      signal.second
        ..r = 250
        ..g = 251
        ..b = 252
        ..blinkPeriod = 253
        ..blinkOffTime = 254
        ..glowWidth = 255
        ..glowHeight = 128;

      final bytes = signal.encode();
      expect(bytes.length, TubeDisplay.encodedSize * 2);

      final back = ComputerSignal()..decode(bytes);
      expect(back.first, signal.first);
      expect(back.second, signal.second);
    });

    test('a short byte array leaves the defaults', () {
      final signal = ComputerSignal()..decode(const [1, 2, 3]);
      expect(signal.first, TubeDisplay());
      expect(signal.second, TubeDisplay());
    });

    test('the default signal still encodes both displays', () {
      expect(ComputerSignal().encode().length, TubeDisplay.encodedSize * 2);
    });
  });
}
