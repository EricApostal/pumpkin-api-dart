import 'dart:typed_data';

import 'package:create/src/core/byte_buf.dart';
import 'package:create/src/core/config.dart';
import 'package:create/src/core/config_models.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/core/ordered_registry.dart';
import 'package:create/src/core/payload.dart';
import 'package:create/src/core/pos.dart';
import 'package:create/src/core/services.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  group('OrderedRegistry', () {
    test('keeps registration order and rejects duplicates', () {
      final r = OrderedRegistry<int>('t')
        ..add('b', 1)
        ..add('a', 2);
      expect(r.keys, ['b', 'a']);
      expect(() => r.add('a', 3), throwsA(isA<DuplicateRegistrationException>()));
    });

    test('canonical order comes first, the rest follows, report lists the gaps', () {
      final r = OrderedRegistry<int>('t')
        ..add('x', 1)
        ..add('y', 2)
        ..add('z', 3);
      r.useOrder(['z', 'q', 'x']);
      expect(r.keys, ['z', 'x', 'y']);
      expect(r.indexOf('y'), 2);
      expect(r.report.missing, ['q']);
      expect(r.report.extra, ['y']);
    });
  });

  test('packPos round trips', () {
    for (final p in [(0, 0, 0), (-1, -64, 5), (33554431, 2047, -33554432), (123, -2048, -9)]) {
      expect(unpackPos(packPos(p.$1, p.$2, p.$3)), p);
    }
    final w = PacketWriter()..writeBlockPos((-5, 70, 12));
    expect(PacketReader(w.toBytes()).readLong(), packPos(-5, 70, 12));
  });

  group('byte buf', () {
    test('primitives round trip', () {
      final bytes = PacketBuffer.encode((w) {
        w.writeVarInt(300);
        w.writeVarLong(1 << 40);
        w.writeString('création');
        w.writeBlockPos((1, -2, 3));
        w.writeVec3((1.5, -2, 3));
        w.writeUuid('00112233-4455-6677-8899-aabbccddeeff');
        w.writeVarIntList([1, 2, 3]);
        w.writeId('create:shaft');
      });
      final r = PacketReader(bytes);
      expect(r.readVarInt(), 300);
      expect(r.readVarLong(), 1 << 40);
      expect(r.readString(), 'création');
      expect(r.readBlockPos(), (1, -2, 3));
      expect(r.readVec3(), (1.5, -2.0, 3.0));
      expect(r.readUuid(), '00112233-4455-6677-8899-aabbccddeeff');
      expect(r.readVarIntList(), [1, 2, 3]);
      expect(r.readId(), 'create:shaft');
      r.expectEnd();
    });

    test('network nbt round trips', () {
      final tag = NbtValue.compound({
        'a': const NbtValue.int32(-7),
        'b': const NbtValue.string('hé'),
        'c': NbtValue.list([const NbtValue.long(1), const NbtValue.long(2)]),
        'd': NbtValue.compound({'e': const NbtValue.byte(-1), 'f': const NbtValue.double64(2.5)}),
        'g': const NbtValue.intArray([1, 2]),
        'h': const NbtValue.longArray([1 << 40]),
        'i': const NbtValue.byteArray([1, -2]),
        'j': const NbtValue.float(0.5),
        'k': const NbtValue.short(300),
      });
      final decoded = NetworkNbt.decode(NetworkNbt.encode(tag))!.asCompound;
      expect(decoded.keys, tag.asCompound.keys);
      expect(decoded['a']!.value, -7);
      expect(decoded['b']!.value, 'hé');
      expect((decoded['c']!.value as List<NbtValue>).map((e) => e.value), [1, 2]);
      expect(decoded['d']!.asCompound['f']!.value, 2.5);
      expect(decoded['h']!.value, [1 << 40]);
      expect(NetworkNbt.decode(NetworkNbt.encode(null)), isNull);
    });
  });

  group('config', () {
    test('defaults, partial sections and write back', () {
      final c = CreateConfig.parse('{"core": {"debug_smoke_test": true, "modules": {"kinetics": false}}}');
      expect(c.core.debugSmokeTest, isTrue);
      expect(c.core.saveIntervalTicks, 20);
      expect(c.core.modVersion, createModVersion);
      expect(c.moduleEnabled('kinetics'), isFalse);
      expect(c.moduleEnabled('trains'), isTrue);
      expect(c.needsWrite, isTrue);
      expect(c.toJsonString(), contains('"save_interval_ticks": 20'));
    });

    test('invalid file falls back to defaults with a warning', () {
      final c = CreateConfig.parse('{nope');
      expect(c.core.neoforge, isTrue);
      expect(c.warnings, isNotEmpty);
      final d = CreateConfig.parse('{"core": {"save_interval_ticks": "x"}}');
      expect(d.core.saveIntervalTicks, 20);
      expect(d.warnings, isNotEmpty);
    });
  });

  group('payloads', () {
    final codec = PayloadCodec<int>.buffer(write: (w, v) => w.writeVarInt(v), read: (r) => r.readVarInt());

    test('ids, declared order and dispatch', () async {
      final reg = PayloadRegistry<String>();
      final got = <(String, int)>[];
      reg.serverbound<int>('ping', codec, (p, v) => got.add((p, v)));
      final out = reg.clientbound<int>('catnip:pong', codec);
      expect(reg.ids, ['create:ping', 'catnip:pong']);
      expect(reg.declared.map((d) => d.serverbound), [true, false]);
      await reg.serverboundFor('create:ping')!.dispatch('steve', Uint8List.fromList([5]));
      expect(got, [('steve', 5)]);

      final sent = <String>[];
      out.attach((p, ch, data) async => sent.add('$p $ch ${data.length}'));
      await out.send('alex', 3);
      expect(sent, ['alex catnip:pong 1']);
      expect(() => reg.serverbound<int>('ping', codec, (_, _) {}), throwsA(isA<DuplicateChannelException>()));
    });
  });

  test('services', () {
    final s = CreateServices()..provide<String>('x');
    expect(s.require<String>(), 'x');
    expect(s.find<int>(), isNull);
    expect(() => s.require<int>(), throwsA(isA<MissingServiceException>()));
  });
}
