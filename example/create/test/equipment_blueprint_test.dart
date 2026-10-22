// The blueprint's geometry, the ingredient filters `BlueprintItem.assignCompleteRecipe` writes
// into the grid cells, the crafting match (`BlueprintEntity.calculateCraftingResult`) and the
// ghost slot shift-click (`GhostItemMenu.quickMoveStack`).
import 'dart:convert';

import 'package:create/src/common/ghost_menu_layout.dart' show GhostMenu;
import 'package:create/src/content/components.dart' show createComponents;
import 'package:create/src/api/registry/create_registries.dart'
    show CreateBuiltInRegistries, CreateRegistries;
import 'package:create/src/core/nbt.dart';
import 'package:create/src/equipment/blueprint/blueprint_geometry.dart';
import 'package:create/src/equipment/blueprint/blueprint_rules.dart';
import 'package:create/src/equipment/model/dir.dart';
import 'package:create/src/equipment/toolbox/toolbox_model.dart' show TStack;
import 'package:create/src/logistics/filter/filter_item_stack.dart';
import 'package:create/src/logistics/filter/item_attribute.dart';
import 'package:create/src/logistics/model/package.dart' show PackageComponents;
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_wire.dart';
import 'package:create/src/protocol/item_stack.dart' show ItemIdResolver;
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketBuffer, VanillaIds;
import 'package:test/test.dart';

/// The menu slot of the ghost slot [i] of the blueprint menu (`36 + i`).
int ghostSlot(int i) => GhostMenu.blueprint.ghostSlot(i);

/// The item id table of a server with the plugin items the tests use (`ctx.ids` in the plugin):
/// a custom item follows the vanilla table, so the test numbers them past it.
final ItemIdResolver _ids = ItemIdResolver.vanilla(
  custom: (key) => switch (key) {
    'create:brass_ingot' => _brassId,
    _ => null,
  },
  customKey: (id) => switch (id) {
    _brassId => 'create:brass_ingot',
    _ => null,
  },
);

/// The id the test assigns to `create:brass_ingot`.
const int _brassId = 100000;

/// The wire that decodes the ghost slots of a list filter (`LgRuntime.wire` on a server). The
/// vanilla component ids keep the components of an entry (`minecraft:damage`) readable.
StackWire _wire() => StackWire(
  items: _ids,
  componentIdOf: VanillaIds.dataComponentTypes.idOf,
  componentNameOf: VanillaIds.dataComponentTypes.keyOf,
);

/// The bytes of the component [key] of [s] (`null` when it has none), mapped through the
/// production conversion, so a protocol name and a registry key both work here.
List<int>? compOf(TStack s, String key) {
  for (final (name, bytes) in s.comps) {
    if (blueprintComponentKey(name) == key) return bytes;
  }
  return null;
}

/// The `(registry key, bytes)` pairs of the filter stacks contained in [s] (`StackWire.readContents`).
List<String?> contentsOf(TStack s) {
  final wire = _wire();
  final bytes = compOf(s, FilterComponents.filterItems);
  if (bytes == null) return const [];
  return [
    for (final slot in PacketBuffer.decode(bytes, wire.readContents))
      slot.isEmpty ? null : slot.key,
  ];
}

/// The attribute entries [s] carries in the private key `FilterItemStack` reads
/// (`FilterComponents.privateAttributes`).
List<Object?> attributeEntriesOf(TStack s) {
  final bytes = compOf(s, 'minecraft:custom_data');
  if (bytes == null) return const [];
  final root = NetworkNbt.decode(bytes)?.asCompound;
  final value = root?[FilterComponents.privateAttributes];
  if (value == null || value.kind != NbtKind.string) return const [];
  return (jsonDecode(value.value as String) as List).cast<Object?>();
}

/// The `custom:` protocol prefix `StackCodec` puts on a Create component.
const String _custom = 'custom:';

/// A `create:filter` grid stack whose 18 slots hold [items], the way `FilterMenu.saveData` writes
/// the list flags.
TStack listFilterOf(List<TStack> items, {bool respectNbt = false, bool blacklist = false}) {
  final wire = _wire();
  final slots = [
    for (var i = 0; i < 18; i++) i < items.length ? blueprintStackValue(items[i]) : LStack.empty,
  ];
  return TStack(
    FilterItemKeys.list,
    1,
    comps: [
      (
        '$_custom${FilterComponents.filterItems}',
        PacketBuffer.encode((w) => wire.writeContents(w, slots)),
      ),
      if (respectNbt) ('$_custom${FilterComponents.respectNbt}', const [1]),
      if (blacklist) ('$_custom${FilterComponents.blacklist}', const [1]),
    ],
  );
}

void main() {
  setUpAll(registerDefaultItemAttributes);

  group('ingredient filters (`BlueprintItem.convertIngredientToFilter`)', () {
    test('an item ingredient becomes that item', () {
      final s = blueprintItemStack('diamond');
      expect(s.key, 'minecraft:diamond');
      expect(s.count, 1, reason: '`new ItemStack(item)`');
      expect(s.comps, isEmpty);
    });

    test('a tag ingredient becomes a `create:attribute_filter` with one `in_tag` entry', () {
      final s = blueprintTagStack('#logs');
      expect(s.key, FilterItemKeys.attribute);
      expect(s.count, 1);
      expect(compOf(s, FilterComponents.whitelistMode), [0], reason: 'WHITELIST_DISJ');
      expect(
        compOf(s, FilterComponents.respectNbt),
        isNull,
        reason: 'Java sets respect_nbt only for a nested (custom) ingredient',
      );
      expect(attributeEntriesOf(s), [
        {
          'attribute': {'type': 'in_tag', 'value': '#minecraft:logs'},
          'inverted': false,
        },
      ]);
      // The filter model reads the same stack back: both components, by registry key.
      expect(blueprintStackValue(s).comps.keys, [
        'create:attribute_filter_whitelist_mode',
        'minecraft:custom_data',
      ]);
    });

    test('several alternatives become a `create:filter` holding all of them', () {
      final s = blueprintAlternativesStack(['create:brass_ingot', 'minecraft:stick'], ids: _ids);
      expect(s.key, FilterItemKeys.list);
      expect(s.count, 1);
      expect(compOf(s, FilterComponents.respectNbt), isNull);
      expect(contentsOf(s).length, 18, reason: 'the filter item handler has 18 slots');
      expect(contentsOf(s).whereType<String>(), ['create:brass_ingot', 'minecraft:stick']);
    });

    test('more than 18 alternatives leave the cell empty', () {
      final many = [for (var i = 0; i < 19; i++) 'minecraft:stone'];
      expect(blueprintAlternativesStack(many, ids: _ids).isEmpty, isTrue);
      final eighteen = [for (var i = 0; i < 18; i++) 'minecraft:stone'];
      expect(blueprintAlternativesStack(eighteen, ids: _ids).key, FilterItemKeys.list);
    });

    test('a compound of one entry is that entry, an empty one is no cell', () {
      final one = blueprintAlternativesStack(['minecraft:stick'], ids: _ids);
      expect(one.key, 'minecraft:stick');
      expect(one.comps, isEmpty);
      expect(blueprintAlternativesStack(const [], ids: _ids).isEmpty, isTrue);
    });
  });

  group('the crafting match (`BlueprintEntity.calculateCraftingResult`)', () {
    setUp(() => ItemAttributeHooks.itemInTag = (key, tag) => tag == 'minecraft:logs' && key == 'minecraft:oak_log');
    tearDown(() => ItemAttributeHooks.itemInTag = (_, _) => false);

    test('a plain item filter still matches itself', () {
      final filter = blueprintItemStack('minecraft:stick');
      expect(blueprintFilterTest(filter, const TStack('minecraft:stick', 1)), isTrue);
      expect(blueprintFilterTest(filter, const TStack('minecraft:diamond', 1)), isFalse);
    });

    test('a written tag filter accepts an item of the tag and rejects another', () {
      final filter = blueprintTagStack('minecraft:logs');
      expect(blueprintFilterTest(filter, const TStack('minecraft:oak_log', 1)), isTrue);
      expect(blueprintFilterTest(filter, const TStack('minecraft:stone', 1)), isFalse);
    });

    test('the list filter of several alternatives accepts each of them', () {
      final filter = blueprintAlternativesStack(['create:brass_ingot', 'minecraft:stick'], ids: _ids);
      expect(blueprintFilterTest(filter, const TStack('create:brass_ingot', 1), wire: _wire()), isTrue);
      expect(blueprintFilterTest(filter, const TStack('minecraft:stick', 1), wire: _wire()), isTrue);
      expect(blueprintFilterTest(filter, const TStack('minecraft:stone', 1), wire: _wire()), isFalse);
    });

    test('a blacklist list filter inverts the entries', () {
      final filter = listFilterOf([const TStack('minecraft:stone', 1)], blacklist: true);
      expect(blueprintFilterTest(filter, const TStack('minecraft:stone', 1), wire: _wire()), isFalse);
      expect(blueprintFilterTest(filter, const TStack('minecraft:dirt', 1), wire: _wire()), isTrue);
    });

    test('respect_nbt compares the components of the entries', () {
      final named = TStack('minecraft:stone', 1, comps: [('damage', const [1])]);
      final loose = listFilterOf([named]);
      final strict = listFilterOf([named], respectNbt: true);
      expect(blueprintFilterTest(loose, const TStack('minecraft:stone', 1), wire: _wire()), isTrue);
      expect(blueprintFilterTest(strict, const TStack('minecraft:stone', 1), wire: _wire()), isFalse);
      expect(blueprintFilterTest(strict, named, wire: _wire()), isTrue);
    });

    test('a list filter without filter items matches nothing (empty whitelist)', () {
      const empty = TStack(FilterItemKeys.list, 1);
      expect(blueprintFilterTest(empty, const TStack('minecraft:stone', 1)), isFalse);
    });

    test('a package filter matches a package by its address', () {
      // The address is a `text` component on the host (`create:package_address`), so the grid keeps
      // the wire form and the match decodes it (`PackageItem.getAddress`).
      List<int> address(String value) => PacketBuffer.encode((w) => w.writeString(value));
      final filter = TStack(
        FilterItemKeys.package,
        1,
        comps: [('custom:${PackageComponents.address}', address('factory/1'))],
      );
      final box = TStack(
        'create:cardboard_package_12x12',
        1,
        comps: [('custom:${PackageComponents.address}', address('factory/1'))],
      );
      final other = TStack(
        'create:cardboard_package_12x12',
        1,
        comps: [('custom:${PackageComponents.address}', address('factory/2'))],
      );
      expect(blueprintFilterTest(filter, box, wire: _wire()), isTrue);
      expect(blueprintFilterTest(filter, other, wire: _wire()), isFalse);
      expect(
        blueprintFilterTest(filter, const TStack('minecraft:stone', 1), wire: _wire()),
        isFalse,
        reason: 'a package filter only matches packages',
      );
    });

    test('an in_tag entry cannot be written through the host component API', () {
      // `create:attribute_filter_matched_attributes` is the one approximated codec description
      // (`content/components.dart:104-114`): `ItemAttribute` is a registry dispatch, so the host
      // checks the value against `list((varint, flag))` and a payload-bearing attribute type (a
      // tag is a text payload, `components.dart:228-230`) leaves bytes over.
      final codec = createComponents
          .firstWhere((c) => c.key == FilterComponents.matchedAttributes)
          .codec;
      final types = CreateBuiltInRegistries.entries[CreateRegistries.itemAttributeType]!;
      final inTag = types.indexOf('create:in_tag');
      final placeable = types.indexOf('create:placeable');
      expect(inTag, greaterThanOrEqualTo(0));
      expect(placeable, greaterThanOrEqualTo(0));
      List<int> entry(int typeId, {String? tag}) => PacketBuffer.encode((w) {
        w.writeVarInt(1);
        w.writeVarInt(typeId);
        if (tag == null) {
          w.writeBool(false);
        } else {
          w.writeString(tag);
        }
      });
      expect(codec.accepts(entry(placeable)), isTrue);
      expect(codec.accepts(entry(inTag, tag: 'minecraft:logs')), isFalse);
    });
  });

  group('the ghost slot shift-click (`GhostItemMenu.quickMoveStack`)', () {
    test('the 11 ghost slots sit behind the 36 mirror slots', () {
      expect(GhostMenu.blueprint.ghostSlots, 11);
      expect(ghostSlot(0), 36);
      expect(ghostSlot(10), 46);
    });

    test('a shift-click on a mirror slot copies one item into the first empty ghost slot', () {
      final items = List<TStack>.filled(11, TStack.empty);
      items[0] = const TStack('create:filter', 1);
      expect(applyBlueprintQuickMove(items, menuSlot: 5, source: const TStack('minecraft:iron_ingot', 16)), 1);
      expect(items[1].key, 'minecraft:iron_ingot');
      expect(items[1].count, 1, reason: '`copy.setCount(1)`');
      expect(items[0].key, 'create:filter', reason: 'the occupied slot is left alone');
    });

    test('a copied filter keeps its components', () {
      final filter = blueprintTagStack('minecraft:logs');
      final items = List<TStack>.filled(11, TStack.empty);
      expect(applyBlueprintQuickMove(items, menuSlot: 0, source: filter), 0);
      expect(items[0].key, FilterItemKeys.attribute);
      expect(items[0].count, 1);
      expect(items[0].comps.length, filter.comps.length);
      expect(compOf(items[0], FilterComponents.whitelistMode), [0]);
    });

    test('a shift-click on a ghost slot takes one item out of it', () {
      final items = List<TStack>.filled(11, TStack.empty);
      items[3] = const TStack('minecraft:iron_ingot', 3);
      expect(applyBlueprintQuickMove(items, menuSlot: ghostSlot(3), source: TStack.empty), 3);
      expect(items[3].count, 2);
      expect(applyBlueprintQuickMove(items, menuSlot: ghostSlot(3), source: TStack.empty), 3);
      expect(items[3].count, 1);
      expect(applyBlueprintQuickMove(items, menuSlot: ghostSlot(3), source: TStack.empty), 3);
      expect(items[3].isEmpty, isTrue);
      expect(applyBlueprintQuickMove(items, menuSlot: ghostSlot(3), source: TStack.empty), -1);
    });

    test('a full grid and an empty source change nothing', () {
      final full = List<TStack>.filled(11, const TStack('minecraft:stone', 1));
      expect(applyBlueprintQuickMove(full, menuSlot: 2, source: const TStack('minecraft:iron_ingot', 1)), -1);
      expect(full.every((s) => s.key == 'minecraft:stone'), isTrue);
      final empty = List<TStack>.filled(11, TStack.empty);
      expect(applyBlueprintQuickMove(empty, menuSlot: 2, source: TStack.empty), -1);
      expect(empty.every((s) => s.isEmpty), isTrue);
      expect(applyBlueprintQuickMove(empty, menuSlot: -1, source: const TStack('minecraft:stone', 1)), -1);
    });
  });

  test('size 1 on a north wall', () {
    const g = BlueprintGeometry(direction: Dir.north, verticalOrientation: Dir.down, size: 1, blockPos: (0, 0, 0));
    final p = g.entityPosition;
    expect(p.$1, 0.5);
    expect(p.$3, closeTo(0.96875, 1e-9));
    final b = g.boundingBox;
    expect(b.$1, closeTo(0, 1e-9));
    expect(b.$4, closeTo(1, 1e-9));
    expect(b.$6 - b.$3, closeTo(1 / 16, 1e-9));
    expect(g.rotation, (180.0, 0.0));
    expect(g.supportPositions, [(0, 0, 1)]);
  });

  test('size 2 shifts by half a block up and sideways', () {
    const g = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 2, blockPos: (10, 5, 10));
    final b = g.boundingBox;
    expect(b.$4 - b.$1, closeTo(2, 1e-9));
    expect(b.$5 - b.$2, closeTo(2, 1e-9));
    // south facing: counter clockwise is east, shifted by +0.5, and up by +0.5
    expect((b.$1 + b.$4) / 2, closeTo(11, 1e-9));
    expect((b.$2 + b.$5) / 2, closeTo(6, 1e-9));
    expect(g.supportPositions.length, 4);
  });

  test('size 3 covers 3 by 3 blocks', () {
    const g = BlueprintGeometry(direction: Dir.east, verticalOrientation: Dir.down, size: 3, blockPos: (0, 0, 0));
    expect(g.supportPositions.length, 9);
    expect(g.supportPositions.toSet().length, 9);
    expect(g.supportPositions.every((p) => p.$1 == -1), isTrue);
    expect(g.coveredBlocks.length, 9);
    expect(g.rotation, (270.0, 0.0));
  });

  test('on the floor the orientation sets the yaw', () {
    const g = BlueprintGeometry(direction: Dir.up, verticalOrientation: Dir.east, size: 1, blockPos: (0, 0, 0));
    expect(g.rotation, (180 + 270.0, -90.0));
    final b = g.boundingBox;
    expect(b.$5 - b.$2, closeTo(1 / 16, 1e-9));
    const down = BlueprintGeometry(direction: Dir.down, verticalOrientation: Dir.north, size: 1, blockPos: (0, 0, 0));
    expect(down.rotation.$2, 90.0);
  });

  test('sections of a 3 by 3 blueprint', () {
    const g = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 3, blockPos: (0, 0, 0));
    // the centre of the entity is section 4 (x = 1, y = 1)
    expect(g.sectionAt((0, 0, 0), yRot: 0, xRot: 0), 4);
    // lower left corner of the plane
    expect(g.sectionAt((-1.4, -1.4, 0), yRot: 0, xRot: 0), 0);
    expect(g.sectionAt((1.4, 1.4, 0), yRot: 0, xRot: 0), 8);
    const one = BlueprintGeometry(direction: Dir.south, verticalOrientation: Dir.down, size: 1, blockPos: (0, 0, 0));
    expect(one.sectionAt((0.3, 0.2, 0), yRot: 0, xRot: 0), 0);
  });

  test('placement orientation', () {
    expect(blueprintPlacementFor(Dir.north, Dir.east).vertical, Dir.down);
    expect(blueprintPlacementFor(Dir.up, Dir.east).vertical, Dir.east);
  });
}
