import 'dart:convert';
import 'dart:typed_data';

import 'package:create/src/api/registry/create_registries.dart';
import 'package:create/src/content/components.dart';
import 'package:create/src/core/byte_buf.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// One value of [codec], encoded the way a NeoForge client writes it. The
/// shapes only need to be well formed: the point of the test is that the reader
/// consumes exactly these bytes and copies them back.
Uint8List encodeValue(ComponentCodec codec) => PacketBuffer.encode((w) {
  final end = _writeNode(codec.ops, 0, w);
  if (end != codec.ops.length) throw StateError('Malformed codec: ${codec.ops}');
});

int _writeNode(List<ComponentCodecOp> ops, int index, PacketWriter w) {
  final op = ops[index];
  switch (op.kind) {
    case CodecOpKind.varInt:
      w.writeVarInt(300);
    case CodecOpKind.varLong:
      w.writeVarLong(1 << 40);
    case CodecOpKind.flag:
      w.writeBool(true);
    case CodecOpKind.byte:
      w.writeByte(200);
    case CodecOpKind.short:
      w.writeShort(12345);
    case CodecOpKind.int32:
      w.writeInt(-123456789);
    case CodecOpKind.long:
      w.writeLong(0x0123456789abcdef);
    case CodecOpKind.float32:
      w.writeFloat(1.5);
    case CodecOpKind.float64:
      w.writeDouble(-2.25);
    case CodecOpKind.text:
      w.writeByteArray(utf8.encode('create:test'));
    case CodecOpKind.byteArray:
      w.writeByteArray(const [1, 2, 3, 250]);
    case CodecOpKind.uuid:
      w.writeUuid('00112233-4455-6677-8899-aabbccddeeff');
    case CodecOpKind.fixedBytes:
      w.writeBytes([for (var i = 0; i < op.argument; i++) i & 0xff]);
    case CodecOpKind.nbt:
      w.writeNbt(NbtValue.compound({'k': NbtValue.string('v'), 'n': NbtValue.int32(7)}));
    case CodecOpKind.stack:
      ItemStackData(42, 3).write(w);
    case CodecOpKind.componentPatch:
      ItemComponentPatch(
        added: [(VanillaIds.dataComponentTypes.idOf('damage')!, PacketBuffer.encode((w) => w.writeVarInt(9)))],
      ).write(w);
    case CodecOpKind.optional:
      w.writeBool(true);
      return _writeNode(ops, index + 1, w);
    case CodecOpKind.repeated:
      w.writeVarInt(2);
      for (var i = 0; i < 2; i++) {
        _writeNode(ops, index + 1, w);
      }
      return _nodeEnd(ops, index + 1);
    case CodecOpKind.sequence:
      var next = index + 1;
      for (var i = 0; i < op.argument; i++) {
        next = _writeNode(ops, next, w);
      }
      return next;
  }
  return index + 1;
}

int _nodeEnd(List<ComponentCodecOp> ops, int index) {
  final op = ops[index];
  switch (op.kind) {
    case CodecOpKind.optional || CodecOpKind.repeated:
      return _nodeEnd(ops, index + 1);
    case CodecOpKind.sequence:
      var next = index + 1;
      for (var i = 0; i < op.argument; i++) {
        next = _nodeEnd(ops, next);
      }
      return next;
    default:
      return index + 1;
  }
}

/// Round-trips [value] as the value of the component [typeId] in an item stack.
ItemStackData roundTrip(int typeId, Uint8List value, {int itemId = 42, int count = 1}) {
  final stack = ItemStackData(itemId, count, ItemComponentPatch(added: [(typeId, value)]));
  final bytes = stack.encode();
  final decoded = ItemStackData.decode(bytes);
  expect(decoded, stack);
  expect(decoded.patch.added.single.$2, value, reason: 'the value bytes are copied verbatim');
  expect(decoded.encode(), bytes, reason: 'the stack re-encodes to the same bytes');
  return decoded;
}

void main() {
  group('every Create component round trips in an item stack', () {
    var nextId = 100000;
    for (final component in createComponents.where((c) => !c.approximate)) {
      test(component.key, () {
        final id = nextId++;
        ItemComponents.register(id, copierForCodec(component.codec));
        roundTrip(id, encodeValue(component.codec));
      });
    }
  });

  test('the probe case: a stack with a Create component decodes once its reader is registered', () {
    // The probe reported `Data component type 2011 has no wire reader`.
    const probeId = 2011;
    final filterItems = createComponents.firstWhere((c) => c.key == 'create:filter_items');
    final value = encodeValue(filterItems.codec);
    final bytes = ItemStackData(7, 1, ItemComponentPatch(added: [(probeId, value)])).encode();

    expect(
      () => ItemStackData.decode(bytes),
      throwsA(
        isA<UnsupportedComponentException>().having(
          (e) => e.message,
          'message',
          'Data component type 2011 has no wire reader (register it with ItemComponents.register)',
        ),
      ),
    );

    ItemComponents.register(probeId, copierForCodec(filterItems.codec));
    final decoded = ItemStackData.decode(bytes);
    expect(decoded.itemId, 7);
    expect(decoded.patch.added.single.$1, probeId);
    expect(decoded.patch.added.single.$2, value);
  });

  test('a stack with two Create components and a removal round trips', () {
    final items = createComponents.firstWhere((c) => c.key == 'create:filter_items');
    final respectNbt = createComponents.firstWhere((c) => c.key == 'create:filter_items_respect_nbt');
    ItemComponents.register(300001, copierForCodec(items.codec));
    ItemComponents.register(300002, copierForCodec(respectNbt.codec));

    final stack = ItemStackData(
      42,
      5,
      ItemComponentPatch(
        added: [(300001, encodeValue(items.codec)), (300002, encodeValue(respectNbt.codec))],
        removed: [VanillaIds.dataComponentTypes.idOf('damage')!],
      ),
    );
    final decoded = ItemStackData.decode(stack.encode());
    expect(decoded, stack);
    expect(decoded.patch.added.length, 2);
    expect(decoded.patch.removed, stack.patch.removed);
  });

  test('a Create component nested inside another one decodes', () {
    // `create:filter_items` is a list of optional `ItemStackTemplate`; the nested
    // stack carries `create:filter_items_blacklist`, so the outer reader must
    // recurse through the nested patch.
    const outerId = 301001;
    const nestedId = 301002;
    final blacklist = createComponents.firstWhere((c) => c.key == 'create:filter_items_blacklist');
    ItemComponents.register(nestedId, copierForCodec(blacklist.codec));

    final contents = PacketBuffer.encode((w) {
      w.writeVarInt(1); // one slot
      w.writeBool(true); // present
      w.writeVarInt(42); // item id
      w.writeVarInt(1); // count
      w.writeVarInt(1); // one added component
      w.writeVarInt(0); // none removed
      w.writeVarInt(nestedId);
      w.writeBool(true);
    });
    final items = createComponents.firstWhere((c) => c.key == 'create:filter_items');
    ItemComponents.register(outerId, copierForCodec(items.codec));

    roundTrip(outerId, contents);
  });

  test('registerComponentReaders registers all 57 components by the host id', () {
    final ids = {
      for (var i = 0; i < createComponents.length; i++) createComponents[i].key: 500000 + i,
    };
    final attributeEntries = CreateBuiltInRegistries.entries[CreateRegistries.itemAttributeType]!;
    final attributeIds = {
      for (var i = 0; i < attributeEntries.length; i++) attributeEntries[i]: 600000 + i,
    };
    final warnings = <String>[];
    registerComponentReaders(
      (key) => ids[key],
      attributeTypeId: (key) => attributeIds[key],
      warn: warnings.add,
    );
    expect(warnings, isEmpty);
    expect(createComponents.length, 57);

    for (final c in createComponents) {
      final id = ids[c.key]!;
      if (c.approximate) {
        // A payload-free attribute type, then the full dispatch reader.
        final value = PacketBuffer.encode((w) {
          w.writeVarInt(attributeIds['create:in_tag']!);
          w.writeByteArray(utf8.encode('minecraft:logs'));
        });
        roundTrip(id, value);
      } else {
        roundTrip(id, encodeValue(c.codec));
      }
    }
  });

  test('an unregistered component id still rejects cleanly', () {
    const unknown = 987654;
    final bytes = ItemStackData(1, 1, ItemComponentPatch(added: [(unknown, Uint8List(0))])).encode();
    expect(() => ItemStackData.decode(bytes), throwsA(isA<UnsupportedComponentException>()));
  });

  group('create:attribute_filter_matched_attributes (registry dispatch)', () {
    // Synthetic ids: the reader must use whatever the host assigned.
    const base = 400000;
    final entries = CreateBuiltInRegistries.entries[CreateRegistries.itemAttributeType]!;
    final ids = {for (var i = 0; i < entries.length; i++) entries[i]: base + i};
    final copier = attributeFilterCopier(attributeTypeId: (key) => ids[key]);

    ComponentCodec codecOf(String type) => switch (type) {
      'in_tag' || 'added_by' || 'has_name' || 'book_author' => ComponentCodec.text,
      'in_item_group' => ComponentCodec.optional(ComponentCodec.text),
      'has_enchant' || 'shulker_fill_level' || 'has_color' => ComponentCodec.varInt,
      'has_fluid' => ComponentCodec.optional(ComponentCodec.varInt),
      'book_copy' => ComponentCodec.int32,
      _ => ComponentCodec.sequence(const []),
    };

    test('covers all 28 attribute types', () {
      expect(entries.length, 28);
      expect(attributePayloadCopier('not_a_type'), isNull);
    });

    for (final entry in entries) {
      final type = entry.substring(entry.indexOf(':') + 1);
      test(type, () {
        final payload = encodeValue(codecOf(type));
        final value = PacketBuffer.encode((w) {
          w.writeVarInt(ids[entry]!);
          w.writeBytes(payload);
        });
        ItemComponents.register(401000 + ids[entry]! - base, copier);
        roundTrip(401000 + ids[entry]! - base, value);
      });
    }

    test('an unknown attribute type id rejects cleanly', () {
      final value = PacketBuffer.encode((w) => w.writeVarInt(9999));
      ItemComponents.register(402000, copier);
      final bytes = ItemStackData(1, 1, ItemComponentPatch(added: [(402000, value)])).encode();
      expect(() => ItemStackData.decode(bytes), throwsA(isA<PacketException>()));
    });
  });
}
