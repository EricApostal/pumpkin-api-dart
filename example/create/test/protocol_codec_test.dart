import 'dart:math';
import 'dart:typed_data';

import 'package:create/src/core/byte_buf.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:create/src/protocol/codec_compiler.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:create/src/protocol/wire_values.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// Random values per descriptor, shaped like what the compiled codecs decode to.
final class Gen {
  final Random rnd;
  final Set<NetKind> seen = {};

  Gen(this.rnd);

  int int32() => rnd.nextInt(1 << 32) - (1 << 31);
  int int64() => (rnd.nextInt(1 << 32) << 32) | rnd.nextInt(1 << 32);
  double float32() {
    final d = ByteData(4)..setFloat32(0, rnd.nextDouble() * 400 - 200);
    return d.getFloat32(0);
  }

  String text(int max) => String.fromCharCodes([for (var i = 0, n = rnd.nextInt(min(max, 12) + 1); i < n; i++) 97 + rnd.nextInt(26)]);
  String id() => '${text(6)}a:${text(6)}b';
  String uuid() {
    String h(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-${h(4)}-${h(4)}-${h(12)}';
  }

  NbtValue nbt(int depth) {
    final kind = rnd.nextInt(depth > 2 ? 9 : 11);
    return switch (kind) {
      0 => NbtValue.byte(rnd.nextInt(256) - 128),
      1 => NbtValue.short(rnd.nextInt(65536) - 32768),
      2 => NbtValue.int32(int32()),
      3 => NbtValue.long(int64()),
      4 => NbtValue.float(float32()),
      5 => NbtValue.double64(rnd.nextDouble()),
      6 => NbtValue.string(text(10)),
      7 => NbtValue.byteArray([for (var i = 0; i < rnd.nextInt(4); i++) rnd.nextInt(256) - 128]),
      8 => NbtValue.intArray([for (var i = 0; i < rnd.nextInt(4); i++) int32()]),
      9 => NbtValue.list([for (var i = 0, n = rnd.nextInt(3); i < n; i++) NbtValue.int32(int32())]),
      _ => compound(depth + 1),
    };
  }

  NbtValue compound(int depth) => NbtValue.compound({for (var i = 0, n = rnd.nextInt(3); i < n; i++) 'k${text(4)}$i': nbt(depth)});

  ItemComponentPatch patch() {
    if (rnd.nextBool()) return ItemComponentPatch.empty;
    final customData = VanillaIds.dataComponentTypes.idOf('custom_data')!;
    final damage = VanillaIds.dataComponentTypes.idOf('damage')!;
    final removed = VanillaIds.dataComponentTypes.idOf('unbreakable')!;
    return ItemComponentPatch(
      added: [
        (customData, PacketBuffer.encode((w) => w.writeNbt(compound(0)))),
        (damage, PacketBuffer.encode((w) => w.writeVarInt(rnd.nextInt(1000)))),
      ],
      removed: [removed],
    );
  }

  Object? value(NetType t, Map<String, Object?> scope) {
    seen.add(t.kind);
    switch (t.kind) {
      case NetKind.varint:
        return rnd.nextInt(4) == 0 ? int32() : rnd.nextInt(1 << 20);
      case NetKind.blockState:
        return rnd.nextInt(30000);
      case NetKind.varlong:
      case NetKind.long:
        return int64();
      case NetKind.int:
        return int32();
      case NetKind.short:
        return rnd.nextInt(65536) - 32768;
      case NetKind.byte:
        return rnd.nextInt(256) - 128;
      case NetKind.bool:
        return rnd.nextBool();
      case NetKind.float:
        return float32();
      case NetKind.double:
        return rnd.nextDouble() * 1e6 - 5e5;
      case NetKind.string:
        return text(t.maxLength ?? 20);
      case NetKind.resourceLocation:
        return id();
      case NetKind.uuid:
        return uuid();
      case NetKind.blockPos:
        return (rnd.nextInt(1 << 26) - (1 << 25), rnd.nextInt(4096) - 2048, rnd.nextInt(1 << 26) - (1 << 25));
      case NetKind.vec3:
        return (rnd.nextDouble() * 100, rnd.nextDouble() * -100, rnd.nextDouble());
      case NetKind.vec3i:
        return (int32(), int32(), int32());
      case NetKind.direction:
        return rnd.nextInt(6);
      case NetKind.enumeration:
        return rnd.nextInt(8);
      case NetKind.itemStack:
        return ItemStackData(1 + rnd.nextInt(1500), 1 + rnd.nextInt(64), patch());
      case NetKind.itemStackOptional:
        return rnd.nextInt(4) == 0 ? ItemStackData.empty : ItemStackData(1 + rnd.nextInt(1500), 1 + rnd.nextInt(64), patch());
      case NetKind.fluidStack:
        return FluidStackData(rnd.nextInt(50), 1 + rnd.nextInt(100000), patch());
      case NetKind.fluidStackOptional:
        return rnd.nextInt(4) == 0 ? FluidStackData.empty : FluidStackData(rnd.nextInt(50), 1 + rnd.nextInt(100000), patch());
      case NetKind.nbtCompound:
        return compound(0);
      case NetKind.nbtTag:
        return rnd.nextInt(5) == 0 ? null : nbt(0);
      case NetKind.component:
        return rnd.nextBool() ? NbtValue.string(text(10)) : compound(0);
      case NetKind.bytes:
        return Uint8List.fromList([for (var i = 0, n = rnd.nextInt(min(t.maxLength ?? 16, 16) + 1); i < n; i++) rnd.nextInt(256)]);
      case NetKind.list:
        return <Object?>[for (var i = 0, n = rnd.nextInt(min(t.maxLength ?? 4, 4) + 1); i < n; i++) value(t.element!, scope)];
      case NetKind.map:
        final out = <Object?, Object?>{};
        for (var i = 0, n = rnd.nextInt(4); i < n; i++) {
          final k = value(t.key!, scope);
          if (out.keys.any((e) => deepEquals(e, k))) continue;
          out[k] = value(t.value!, scope);
        }
        return out;
      case NetKind.optional:
        return rnd.nextBool() ? value(t.element!, scope) : null;
      case NetKind.either:
        return rnd.nextBool() ? EitherValue.left(value(t.key!, scope)) : EitherValue.right(value(t.value!, scope));
      case NetKind.custom:
        if ((t.className ?? '').startsWith('SignalBoundary only')) {
          return scope['type'] == 'create:signal' ? <String?>[for (var i = 0; i < 2; i++) rnd.nextBool() ? uuid() : null] : null;
        }
        return struct(t.fields!, null);
      case NetKind.dispatch:
        final v = t.fields![rnd.nextInt(t.fields!.length)];
        return PayloadVariant(v.name, value(v.type, scope));
    }
  }

  Map<String, Object?> struct(List<NetField> fields, String? payloadId) {
    final out = <String, Object?>{};
    final hasSignal = fields.any((f) => f.name == 'signalGroups');
    for (final f in fields) {
      if (payloadId == 'create:sync_rail_graph' && f.name == 'dimensionPalette' && out['packetDeletesGraph'] == true) break;
      if (hasSignal && f.name == 'type') {
        out['type'] = rnd.nextBool() ? 'create:signal' : 'create:other';
        continue;
      }
      out[f.name] = value(f.type, out);
    }
    return out;
  }
}

void main() {
  final schemas = PayloadSchemas.manifest;

  test('the manifest compiles: 119 payloads, 67 serverbound and 52 clientbound', () {
    expect(schemas.byId.length, 119);
    expect(schemas.all.where((s) => s.direction == NetDirection.serverbound).length, 67);
    expect(schemas.all.where((s) => s.direction == NetDirection.clientbound).length, 52);
  });

  group('round trip of every payload', () {
    final gen = Gen(Random(42));
    for (final schema in schemas.all) {
      test(schema.id, () {
        for (var i = 0; i < 40; i++) {
          final fields = gen.struct(schema.payload.fields, schema.id);
          final bytes = schema.encode(fields);
          final decoded = schema.decode(bytes);
          expect(deepEquals(decoded, fields), isTrue, reason: 'seed $i\n$fields\nvs\n$decoded');
          expect(schema.encode(decoded), bytes, reason: 'bytes are stable (seed $i)');
        }
      });
    }

    test('every field kind of the manifest was exercised', () {
      final used = <NetKind>{};
      void walk(NetType t) {
        used.add(t.kind);
        for (final n in [t.element, t.key, t.value]) {
          if (n != null) walk(n);
        }
        for (final f in t.fields ?? const <NetField>[]) {
          walk(f.type);
        }
      }

      for (final p in networkPayloads) {
        for (final f in p.fields) {
          walk(f.type);
        }
      }
      expect(gen.seen.containsAll(used), isTrue, reason: 'missing ${used.difference(gen.seen)}');
      // Kinds the manifest does not use are covered below.
      expect(used.length, greaterThan(25));
    });
  });

  group('unused kinds round trip', () {
    final gen = Gen(Random(7));
    for (final kind in [NetKind.vec3i, NetKind.fluidStack, NetKind.byte, NetKind.long]) {
      test(kind.name, () {
        final codec = compileType(NetType(kind));
        for (var i = 0; i < 20; i++) {
          final v = gen.value(NetType(kind), {});
          final bytes = PacketBuffer.encode((w) => codec.write(w, v, {}));
          final back = PacketBuffer.decode(bytes, (r) => codec.read(r, {}));
          expect(deepEquals(back, v), isTrue);
        }
      });
    }
  });

  group('wire layout (golden bytes)', () {
    test('create:configure_stockswitch', () {
      final bytes = schemas['create:configure_stockswitch'].encode({
        'pos': (1, 64, -2),
        'offBelow': 5,
        'onAbove': -1,
        'invert': true,
        'inStacks': false,
      });
      final expected = PacketBuffer.encode((w) {
        w.writeLong(((1 & 0x3FFFFFF) << 38) | ((-2 & 0x3FFFFFF) << 12) | 64);
        w.writeInt(5);
        w.writeInt(-1);
        w.writeBool(true);
        w.writeBool(false);
      });
      expect(bytes, expected);
    });

    test('item stack: count, item id, empty patch', () {
      expect(ItemStackData(7, 3).encode(), [3, 7, 0, 0]);
      expect(ItemStackData.empty.encode(), [0]);
      expect(ItemStackData.decode([0]).isEmpty, isTrue);
      expect(() => ItemStackData.decode([0], allowEmpty: false), throwsA(isA<PacketException>()));
      expect(() => ItemStackData.decode([100, 1, 0, 0]), throwsA(isA<PacketException>()));
    });

    test('item stack with components keeps the bytes', () {
      final id = VanillaIds.dataComponentTypes.idOf('custom_data')!;
      final tag = NbtValue.compound({'a': const NbtValue.int32(1)});
      final raw = PacketBuffer.encode((w) {
        w.writeVarInt(2);
        w.writeVarInt(300);
        w.writeVarInt(1);
        w.writeVarInt(0);
        w.writeVarInt(id);
        w.writeNbt(tag);
      });
      final stack = ItemStackData.decode(raw);
      expect(stack.itemId, 300);
      expect(stack.patch.added.single.$1, id);
      expect(stack.encode(), raw);
    });

    test('an unknown component rejects the stack', () {
      final raw = PacketBuffer.encode((w) {
        w
          ..writeVarInt(1)
          ..writeVarInt(5)
          ..writeVarInt(1)
          ..writeVarInt(0)
          ..writeVarInt(99999);
      });
      expect(() => ItemStackData.decode(raw), throwsA(isA<UnsupportedComponentException>()));
      ItemComponents.register(99999, ItemComponents.copyVarInt);
      final withValue = Uint8List.fromList([...raw, 7]);
      expect(ItemStackData.decode(withValue).encode(), withValue);
    });

    test('dispatch uses the variant index', () {
      final s = schemas['ponder:open_ponder'];
      expect(s.encode({'target': const PayloadVariant('INDEX')}), [0]);
      final scene = s.encode({'target': const PayloadVariant('SCENE', 'ponder:a')});
      expect(scene.first, 2);
      expect(s.decode(scene)['target'], const PayloadVariant('SCENE', 'ponder:a'));
      final port = schemas['create:place_package_port'];
      expect(port.encode({'target': const PayloadVariant('create:train_station', (1, 2, 3)), 'pos': (0, 0, 0)}).first, 1);
    });

    test('the rail graph deletion packet ends after fullWipe', () {
      final s = schemas['create:sync_rail_graph'];
      final bytes = s.encode({'graphId': '00000000-0000-0000-0000-000000000001', 'netId': 4, 'packetDeletesGraph': true, 'fullWipe': false});
      expect(bytes.length, 16 + 4 + 2);
      expect(s.decode(bytes).containsKey('addedNodes'), isFalse);
      // The palette count is a 4 byte int.
      final full = s.encode({
        'graphId': '00000000-0000-0000-0000-000000000001',
        'netId': 4,
        'packetDeletesGraph': false,
        'fullWipe': false,
        'dimensionPalette': ['minecraft:overworld'],
        'removedNodes': <int>[],
        'addedNodes': <Object?, Object?>{},
        'addedEdges': <Object?>[],
        'addedEdgePoints': <Object?>[],
        'removedEdgePoints': <Object?>[],
        'updatedEdgeData': <Object?>[],
        'splitSubGraphs': <Object?, Object?>{},
      });
      expect(full.sublist(22, 26), [0, 0, 0, 1]);
    });
  });

  group('bad data', () {
    final stock = schemas['create:configure_stockswitch'];
    final fields = {'pos': (1, 2, 3), 'offBelow': 1, 'onAbove': 2, 'invert': true, 'inStacks': true};

    test('truncated and trailing bytes', () {
      final bytes = stock.encode(fields);
      expect(() => stock.decode(bytes.sublist(0, bytes.length - 1)), throwsA(isA<PacketException>()));
      expect(() => stock.decode([...bytes, 0]), throwsA(isA<PacketException>()));
    });

    test('wrong field types and missing fields', () {
      expect(() => stock.encode({...fields, 'offBelow': 'x'}), throwsA(isA<PacketException>()));
      expect(() => stock.encode({...fields}..remove('pos')), throwsA(isA<PacketException>()));
      expect(() => stock.encode({...fields, 'pos': (1, 99999, 3)}), throwsA(isA<Object>()));
    });

    test('absurd list counts are rejected before allocating', () {
      final s = schemas['create:linked_controller_input'];
      final bad = PacketBuffer.encode((w) => w.writeVarInt(1 << 30));
      expect(() => s.decode(bad), throwsA(isA<PacketException>()));
      final huge = PacketBuffer.encode((w) => w.writeVarInt(100000));
      expect(() => s.decode(huge), throwsA(isA<PacketException>()));
    });

    test('string and byte array bounds', () {
      final s = schemas['create:configure_station'];
      expect(
        () => s.encode({'pos': (0, 0, 0), 'dropSchedule': false, 'assemblyMode': false, 'name': 'x' * 300}),
        throwsA(isA<PacketException>()),
      );
      final up = schemas['create:upload_schematic'];
      final tooLong = PacketBuffer.encode((w) {
        w
          ..writeVarInt(1)
          ..writeVarLong(2)
          ..writeBool(true)
          ..writeString('a' * 1000, maxLength: 5000);
      });
      expect(() => up.decode(tooLong), throwsA(isA<PacketException>()));
    });

    test('invalid direction and resource location', () {
      final s = schemas['create:glue_effect'];
      final bytes = PacketBuffer.encode((w) {
        w.writeBlockPos((0, 0, 0));
        w.writeVarInt(6);
        w.writeBool(true);
      });
      expect(() => s.decode(bytes), throwsA(isA<PacketException>()));
      final rl = schemas['create:blueprint_complete_recipe'];
      expect(() => rl.encode({'recipeId': 'Bad Id!'}), throwsA(isA<PacketException>()));
    });

    test('random garbage never throws anything but PacketException', () {
      final rnd = Random(1);
      for (final schema in schemas.all) {
        for (var i = 0; i < 30; i++) {
          final data = Uint8List.fromList([for (var j = 0, n = rnd.nextInt(40); j < n; j++) rnd.nextInt(256)]);
          try {
            schema.decode(data);
          } on PacketException {
            // expected
          }
        }
      }
    });
  });
}
