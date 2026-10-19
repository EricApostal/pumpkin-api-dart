import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/schematics/item_requirement.dart';
import 'package:create/src/schematics/nbt_processors.dart';
import 'package:create/src/schematics/schematic_printer.dart';
import 'package:create/src/schematics/schematic_state_filters.dart';
import 'package:create/src/schematics/state_transform.dart';
import 'package:test/test.dart';

List<int> _entity(Map<String, NbtValue> body) =>
    BinaryNbt.write(NbtValue.compound(body));

Map<String, NbtValue> _book({
  required String id,
  required List<NbtValue> pages,
}) => {
  'Book': NbtValue.compound({
    'id': NbtValue.string(id),
    'count': const NbtValue.int32(1),
    'components': NbtValue.compound({
      'minecraft:written_book_content': NbtValue.compound({
        'pages': NbtValue.list(pages),
      }),
    }),
  }),
};

void main() {
  group('state filters', () {
    test('chiseled bookshelf slots start empty', () {
      final state = BState('minecraft:chiseled_bookshelf', {
        'facing': 'north',
        for (var i = 0; i < 6; i++) 'slot_${i}_occupied': 'true',
      });
      final filtered = chiseledBookshelfFilter(null, state);
      for (var i = 0; i < 6; i++) {
        expect(filtered.flag('slot_${i}_occupied'), isFalse);
      }
      expect(filtered['facing'], 'north');
    });
  });

  group('state transform', () {
    test('double chest halves mirror', () {
      const chest = BState('minecraft:chest', {
        'facing': 'north',
        'type': 'left',
        'waterlogged': 'false',
      });
      final mirrored = mirrorState(chest, BlockMirror.leftRight);
      expect(mirrored['facing'], 'south');
      expect(mirrored['type'], 'right');
      expect(mirrorState(mirrored, BlockMirror.leftRight)['type'], 'left');
      expect(
        mirrorState(
          const BState('minecraft:chest', {
            'facing': 'north',
            'type': 'single',
          }),
          BlockMirror.leftRight,
        )['type'],
        'single',
      );
    });

    test('crafter and jigsaw orientation mirror both axes', () {
      const crafter = BState('minecraft:crafter', {'orientation': 'north_up'});
      // LEFT_RIGHT inverts Z: north -> south, up stays up.
      expect(
        mirrorState(crafter, BlockMirror.leftRight)['orientation'],
        'south_up',
      );
      // FRONT_BACK inverts X: north/up are unaffected.
      expect(
        mirrorState(crafter, BlockMirror.frontBack)['orientation'],
        'north_up',
      );
      const vertical = BState('minecraft:jigsaw', {'orientation': 'down_east'});
      expect(
        mirrorState(vertical, BlockMirror.frontBack)['orientation'],
        'down_west',
      );
      // A quarter turn rotates the horizontal part and leaves the vertical part.
      expect(
        rotateState(crafter, BlockRotation.clockwise90)['orientation'],
        'east_up',
      );
    });
  });

  group('entity requirements', () {
    test('an item frame needs the frame and its displayed item', () {
      final nbt = _entity({
        'id': const NbtValue.string('minecraft:item_frame'),
        'Item': NbtValue.compound({
          'id': const NbtValue.string('minecraft:diamond'),
          'count': const NbtValue.int32(3),
        }),
      });
      final requirement = SchematicRequirements().ofEntity(
        'minecraft:item_frame',
        nbt,
      );
      expect(
        requirement.requiredItems.map((r) => r.item),
        containsAll(['minecraft:item_frame', 'minecraft:diamond']),
      );
      expect(
        requirement.requiredItems
            .firstWhere((r) => r.item == 'minecraft:diamond')
            .count,
        3,
      );
    });

    test('an armor stand needs its equipment, not empty slots', () {
      final nbt = _entity({
        'id': const NbtValue.string('minecraft:armor_stand'),
        'equipment': NbtValue.compound({
          'head': NbtValue.compound({
            'id': const NbtValue.string('minecraft:iron_helmet'),
            'count': const NbtValue.int32(1),
          }),
          'mainhand': NbtValue.compound({
            'id': const NbtValue.string('minecraft:air'),
            'count': const NbtValue.int32(1),
          }),
        }),
      });
      final requirement = SchematicRequirements().ofEntity(
        'minecraft:armor_stand',
        nbt,
      );
      final items = requirement.requiredItems.map((r) => r.item).toList();
      expect(items, contains('minecraft:armor_stand'));
      expect(items, contains('minecraft:iron_helmet'));
      expect(items, isNot(contains('minecraft:air')));
    });
  });

  group('NBT processors', () {
    test('a lectern keeps a safe written book', () {
      final data = _entity(
        _book(
          id: 'minecraft:written_book',
          pages: [
            NbtValue.compound({
              'raw': NbtValue.compound({
                'text': const NbtValue.string('hello'),
              }),
            }),
          ],
        ),
      );
      expect(
        processSchematicNbt(
          data,
          isSign: false,
          isClipboard: false,
          isLectern: true,
        ),
        same(data),
      );
    });

    test('a lectern drops a page with a click event', () {
      final data = _entity(
        _book(
          id: 'minecraft:written_book',
          pages: [
            NbtValue.compound({
              'raw': NbtValue.compound({
                'text': const NbtValue.string('click'),
                'click_event': NbtValue.emptyCompound(),
              }),
            }),
          ],
        ),
      );
      expect(
        processSchematicNbt(
          data,
          isSign: false,
          isClipboard: false,
          isLectern: true,
        ),
        isNull,
      );
    });

    test('a lectern keeps a writable book', () {
      final data = _entity(
        _book(
          id: 'minecraft:writable_book',
          pages: [
            NbtValue.compound({
              'raw': NbtValue.compound({
                'click_event': NbtValue.emptyCompound(),
              }),
            }),
          ],
        ),
      );
      expect(
        processSchematicNbt(
          data,
          isSign: false,
          isClipboard: false,
          isLectern: true,
        ),
        same(data),
      );
    });

    test('a creative crate filter keeps only safe components', () {
      final data = _entity({
        'Filter': NbtValue.compound({
          'id': const NbtValue.string('minecraft:stone'),
          'count': const NbtValue.int32(1),
          'components': NbtValue.compound({
            'minecraft:custom_name': NbtValue.compound({
              'text': const NbtValue.string('kept'),
            }),
            'minecraft:custom_data': NbtValue.emptyCompound(),
            'minecraft:enchantments': NbtValue.emptyCompound(),
          }),
        }),
      });
      final out = processSchematicNbt(
        data,
        isSign: false,
        isClipboard: false,
        isCreativeCrate: true,
      );
      expect(out, isNotNull);
      final parsed = BinaryNbt.read(out!)!;
      final filter = parsed.root.asCompound['Filter']!.asCompound;
      final components = filter['components']!.asCompound;
      expect(components.keys.toSet(), {
        'minecraft:custom_name',
        'minecraft:enchantments',
      });
    });
  });

  test('tracks merge their block entities while printing', () {
    expect(SchematicPrinter().mergeableBlocks, contains('create:track'));
  });
}
