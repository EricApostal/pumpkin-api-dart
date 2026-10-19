import 'dart:typed_data';

import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/common/bounds.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/data/pack_format.dart' show gunzip;
import 'package:create/src/schematics/schematic_export.dart';
import 'package:test/test.dart';

NbtValue _doubleList(List<double> values) =>
    NbtValue.list([for (final v in values) NbtValue.double64(v)]);

NbtValue _intList(List<int> values) =>
    NbtValue.list([for (final v in values) NbtValue.int32(v)]);

NbtValue _glueEntity() => NbtValue.compound({
  'pos': _doubleList([1, 0, 1]),
  'blockPos': _intList([1, 0, 1]),
  'nbt': NbtValue.compound({
    'id': const NbtValue.string('create:super_glue'),
    'From': _doubleList([-0.5, 0, -0.5]),
    'To': _doubleList([0.5, 1, 0.5]),
  }),
});

NbtValue _structure() => NbtValue.compound({
  'size': _intList([4, 4, 4]),
  'palette': NbtValue.list([
    NbtValue.compound({'Name': const NbtValue.string('minecraft:stone')}),
    NbtValue.compound({
      'Name': const NbtValue.string('minecraft:structure_void'),
    }),
  ]),
  'blocks': NbtValue.list([
    NbtValue.compound({
      'pos': _intList([0, 0, 0]),
      'state': const NbtValue.int32(0),
    }),
    NbtValue.compound({
      'pos': _intList([1, 0, 0]),
      'state': const NbtValue.int32(1),
    }),
  ]),
  'entities': NbtValue.list([_glueEntity()]),
});

List<Object> _values(NbtValue list) => [
  for (final v in list.value as List<NbtValue>) v.value,
];

Map<String, NbtValue> _roundTrip(Uint8List bytes) {
  final parsed = BinaryNbt.read(gunzip(bytes));
  expect(parsed, isNotNull);
  expect(parsed!.root.kind, NbtKind.compound);
  return parsed.root.asCompound;
}

void main() {
  test('gzipCompress round trips through the pack reader', () {
    final data = List<int>.generate(70000, (i) => i & 0xff);
    expect(gunzip(gzipCompress(data)), Uint8List.fromList(data));
    expect(gunzip(gzipCompress(const [])), isEmpty);
  });

  test('structure void becomes air', () {
    final root = {..._structure().asCompound};
    replaceStructureVoidWithAir(root);
    final palette = root['palette']!.value as List<NbtValue>;
    expect(palette[1].asCompound['Name']!.value, 'minecraft:air');
    expect(palette[0].asCompound['Name']!.value, 'minecraft:stone');
  });

  test('glue boxes are cropped and re-added relative to the area', () {
    final root = {..._structure().asCompound};
    clampGlueBoxes(root, const Aabb(0, 0, 0, 4, 4, 4), const [
      Aabb(1, 1, 1, 3, 2, 3),
    ]);
    final entities = root['entities']!.value as List<NbtValue>;
    expect(entities, hasLength(1));
    final entity = entities.single.asCompound;
    // SuperGlueEntity.resetPositionToBB: (centre x, min y, centre z), relative to the area.
    expect(_values(entity['pos']!), [2.0, 1.0, 2.0]);
    expect(_values(entity['blockPos']!), [2, 1, 2]);
    final nbt = entity['nbt']!.asCompound;
    expect(nbt['id']!.value, 'create:super_glue');
    // writeAdditional stores the box relative to the entity position.
    expect(_values(nbt['From']!), [-1.0, 0.0, -1.0]);
    expect(_values(nbt['To']!), [1.0, 1.0, 1.0]);
  });

  test('existing glue entities are removed even without cropped boxes', () {
    final root = {..._structure().asCompound};
    clampGlueBoxes(root, const Aabb(0, 0, 0, 4, 4, 4), const []);
    expect(root['entities']!.value, isEmpty);
  });

  test(
    'prepareSchematicExport applies both changes and keeps other entities',
    () {
      final root = {..._structure().asCompound};
      final entities = List<NbtValue>.of(
        root['entities']!.value as List<NbtValue>,
      );
      entities.add(
        NbtValue.compound({
          'pos': _doubleList([0, 0, 0]),
          'blockPos': _intList([0, 0, 0]),
          'nbt': NbtValue.compound({
            'id': const NbtValue.string('minecraft:armor_stand'),
          }),
        }),
      );
      root['entities'] = NbtValue.list(entities);
      final saved = gzipCompress(BinaryNbt.write(NbtValue.compound(root)));

      final out = prepareSchematicExport(
        saved,
        area: const Aabb(0, 0, 0, 4, 4, 4),
        croppedGlueBoxes: const [Aabb(0, 0, 0, 2, 1, 2)],
      );
      final result = _roundTrip(out);
      final palette = result['palette']!.value as List<NbtValue>;
      expect(palette[1].asCompound['Name']!.value, 'minecraft:air');
      final outEntities = result['entities']!.value as List<NbtValue>;
      expect(outEntities, hasLength(2));
      expect(
        outEntities
            .map(
              (e) => (e.asCompound['nbt']!.asCompound['id']!.value as String),
            )
            .toSet(),
        {'minecraft:armor_stand', 'create:super_glue'},
      );
    },
  );

  test('unreadable input is returned unchanged', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(
      prepareSchematicExport(bytes, area: const Aabb(0, 0, 0, 1, 1, 1)),
      bytes,
    );
  });
}
