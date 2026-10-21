// `CarriageSyncData.write` / `read` against Java's `FriendlyByteBuf` layout, byte for byte.
//
// The value is the entity data of a carriage (`CarriageContraptionEntity.CARRIAGE_DATA`, serializer
// `create:carriage_data`), so its layout is a wire contract with the client:
//
//   writeBoolean(leadingCarriage)                       CarriageSyncData.java:75
//   writeBoolean(fallbackLocations != null)             :76
//   if fallback:                                        :78-84
//     VecHelper.write(contraptionAnchor)                (three doubles)
//     VecHelper.write(rotationAnchors.getFirst())
//     VecHelper.write(rotationAnchors.getSecond())
//     return
//   for (Pair<Couple<Integer>, Float> pair : wheelLocations) {   :86-93
//     writeBoolean(pair == null); if (pair == null) break;
//     pair.getFirst().forEach(buffer::writeInt)         (two ints)
//     writeFloat(pair.getSecond())
//   }
//   writeFloat(distanceToDestination)                   :94
//
// Two properties are easy to get wrong and desynchronise every field after them: the loop writes
// its `pair == null` boolean *before* breaking (so a short list carries a terminator boolean and a
// full list of four carries none), and the fallback branch returns before
// `distanceToDestination`.
import 'dart:typed_data';

import 'package:create/src/common/common.dart';
import 'package:create/src/trains/entity/carriage_sync_data.dart';
import 'package:test/test.dart';

/// The expected bytes of [write] as Java would produce them, built from `ByteData` rather than from
/// the port's `PacketWriter` so a wrong width or endianness in the port cannot hide behind it.
final class _JavaBytes {
  final BytesBuilder _out = BytesBuilder();

  void _add(ByteData data) => _out.add(data.buffer.asUint8List());

  void boolean(bool value) => _out.addByte(value ? 1 : 0);

  void int32(int value) {
    final d = ByteData(4)..setInt32(0, value);
    _add(d);
  }

  void float32(double value) {
    final d = ByteData(4)..setFloat32(0, value);
    _add(d);
  }

  void float64(double value) {
    final d = ByteData(8)..setFloat64(0, value);
    _add(d);
  }

  /// `VecHelper.write`: `writeDouble` three times.
  void vec3((double, double, double) v) {
    float64(v.$1);
    float64(v.$2);
    float64(v.$3);
  }

  /// A wheel entry: the `pair == null` flag (which is also the loop's terminator), then the two
  /// node ids and the position -- but only when the entry is present.
  void wheel({
    required bool isNull,
    int node1 = 0,
    int node2 = 0,
    double position = 0,
  }) {
    boolean(isNull);
    if (isNull) return;
    int32(node1);
    int32(node2);
    float32(position);
  }

  Uint8List toBytes() => _out.toBytes();
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  group('CarriageSyncData codec', () {
    test('a short wheel list carries a terminator boolean, then the distance', () {
      final data = CarriageSyncData()
        ..leadingCarriage = false
        ..wheelLocations[0] = Pair.of(Couple.create(17, 42), 1.5)
        ..wheelLocations[1] = Pair.of(Couple.create(-2, 3), 0.25)
        ..distanceToDestination = 12.5;

      final expected = _JavaBytes()
        ..boolean(false) // leadingCarriage
        ..boolean(false) // fallbackLocations == null
        ..wheel(isNull: false, node1: 17, node2: 42, position: 1.5)
        ..wheel(isNull: false, node1: -2, node2: 3, position: 0.25)
        ..wheel(isNull: true) // `pair == null`: the terminator, written before the break
        ..float32(12.5);
      final bytes = data.toBytes();

      expect(_hex(bytes), _hex(expected.toBytes()));
      // The same bytes written out literally, so a broken `_JavaBytes` helper cannot pass:
      //   00 00                leading=false, fallback=false
      //   00 00000011 0000002a 3fc00000     wheel 0: present, 17, 42, 1.5f
      //   00 fffffffe 00000003 3e800000     wheel 1: present, -2, 3, 0.25f
      //   01                                 wheel 2: null -> break
      //   41480000                           distance 12.5f
      expect(_hex(bytes), '00 00 00 00 00 00 11 00 00 00 2a 3f c0 00 00 '
          '00 ff ff ff fe 00 00 00 03 3e 80 00 00 01 41 48 00 00');

      final back = CarriageSyncDataSerializer.decode(bytes);
      expect(back.leadingCarriage, isFalse);
      expect(back.fallbackLocations, isNull);
      expect(back.wheelLocations[0]!.getFirst().getFirst(), 17);
      expect(back.wheelLocations[0]!.getFirst().getSecond(), 42);
      expect(back.wheelLocations[0]!.getSecond(), 1.5);
      expect(back.wheelLocations[1]!.getFirst().getFirst(), -2);
      expect(back.wheelLocations[1]!.getFirst().getSecond(), 3);
      expect(back.wheelLocations[1]!.getSecond(), 0.25);
      expect(back.wheelLocations[2], isNull);
      expect(back.wheelLocations[3], isNull);
      expect(back.distanceToDestination, 12.5);
    });

    test('four wheels write no terminator before the distance', () {
      final data = CarriageSyncData()..leadingCarriage = true;
      for (var i = 0; i < 4; i++) {
        data.wheelLocations[i] = Pair.of(Couple.create(i, i + 1), i + 0.5);
      }
      data.distanceToDestination = -1.25;

      final expected = _JavaBytes()
        ..boolean(true)
        ..boolean(false);
      for (var i = 0; i < 4; i++) {
        expected.wheel(isNull: false, node1: i, node2: i + 1, position: i + 0.5);
      }
      expected.float32(-1.25);

      final bytes = data.toBytes();
      expect(_hex(bytes), _hex(expected.toBytes()));
      // 2 + 4 * (1 + 4 + 4 + 4) + 4: no extra boolean between the fourth wheel and the distance.
      expect(bytes, hasLength(2 + 4 * 13 + 4));

      final back = CarriageSyncDataSerializer.decode(bytes);
      expect(back.leadingCarriage, isTrue);
      expect(back.fallbackLocations, isNull);
      for (var i = 0; i < 4; i++) {
        expect(back.wheelLocations[i]!.getFirst().getFirst(), i);
        expect(back.wheelLocations[i]!.getFirst().getSecond(), i + 1);
        expect(back.wheelLocations[i]!.getSecond(), i + 0.5);
      }
      expect(back.distanceToDestination, -1.25);
    });

    test('the fallback branch writes three vectors and no distance', () {
      final data = CarriageSyncData()
        ..leadingCarriage = true
        ..fallbackLocations = Pair.of(
          (1.5, 2.0, -3.25),
          Couple.create((4.0, 5.0, 6.0), (7.0, 8.0, 9.0)),
        )
        // Written only in the wheel branch: the fallback branch returns before it.
        ..distanceToDestination = 99.0;

      final expected = _JavaBytes()
        ..boolean(true)
        ..boolean(true)
        ..vec3((1.5, 2.0, -3.25))
        ..vec3((4.0, 5.0, 6.0))
        ..vec3((7.0, 8.0, 9.0));
      final bytes = data.toBytes();

      expect(_hex(bytes), _hex(expected.toBytes()));
      // 2 booleans + 3 vectors of three doubles.
      expect(bytes, hasLength(2 + 3 * 24));

      final back = CarriageSyncDataSerializer.decode(bytes);
      expect(back.leadingCarriage, isTrue);
      expect(back.fallbackLocations, isNotNull);
      expect(back.fallbackLocations!.getFirst(), (1.5, 2.0, -3.25));
      expect(back.fallbackLocations!.getSecond().getFirst(), (4.0, 5.0, 6.0));
      expect(back.fallbackLocations!.getSecond().getSecond(), (7.0, 8.0, 9.0));
      // The reader leaves `distanceToDestination` at its default, as Java's constructor does.
      expect(back.distanceToDestination, 0);
    });

    test('the metadata entry is the serializer id, then the value', () {
      // `SynchedEntityData` writes the serializer's registered id as a VarInt in front of the
      // value (`CarriageSyncDataSerializer` id 12, `registries.g.dart:4064`).
      final previous = CarriageSyncDataSerializer.serializerId;
      CarriageSyncDataSerializer.serializerId = 12;
      addTearDown(() => CarriageSyncDataSerializer.serializerId = previous);

      final data = CarriageSyncData()
        ..wheelLocations[0] = Pair.of(Couple.create(5, 6), 2.5);
      final entry = CarriageSyncDataSerializer.encodeEntry(data);

      expect(entry, isNotNull);
      expect(entry![0], 12, reason: 'a VarInt below 128 is one byte');
      expect(entry.sublist(1), CarriageSyncDataSerializer.encode(data));
      // The value is the same bytes the stream codec writes: a VarInt prefix is all that is added.
      expect(entry.sublist(1), data.toBytes());
    });
  });
}
