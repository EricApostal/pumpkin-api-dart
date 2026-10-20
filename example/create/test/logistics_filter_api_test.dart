// The `ItemFilterApi` provider the logistics module installs, the `in_item_group` attribute, and
// the conveyance filter slot that asks the provider (`filtering.dart`).
import 'dart:convert';

import 'package:create/src/api/filter_api.dart';
import 'package:create/src/conveyance/items/filter_match.dart' as filtering;
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/core/services.dart';
import 'package:create/src/logistics/filter/filter_api.dart';
import 'package:create/src/logistics/filter/filter_item_stack.dart';
import 'package:create/src/logistics/filter/item_attribute.dart';
import 'package:create/src/logistics/filter/logistics_services.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_wire.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketBuffer, VanillaIds;
import 'package:test/test.dart';

StackWire _wire() => StackWire(
  items: ItemIdResolver.vanilla(),
  // The vanilla component ids, so the entries of a list filter keep their components.
  componentIdOf: VanillaIds.dataComponentTypes.idOf,
  componentNameOf: VanillaIds.dataComponentTypes.keyOf,
);

/// A `create:filter` list filter whose ghost slots hold [items] (`AllDataComponents.FILTER_ITEMS`).
FilterItemValue _listFilter(
  List<LStack> items, {
  bool blacklist = false,
  bool respectNbt = false,
}) {
  final wire = _wire();
  final contents = PacketBuffer.encode(
    (w) => wire.writeContents(w, [...items, LStack.empty]),
  );
  return FilterItemValue(
    FilterItemKeys.list,
    components: [
      (FilterComponents.filterItems, contents),
      (FilterComponents.respectNbt, [respectNbt ? 1 : 0]),
      (FilterComponents.blacklist, [blacklist ? 1 : 0]),
    ],
  );
}

ItemFilterApi _api() {
  ItemFilterApiAdapter.wire = _wire;
  return const ItemFilterApiAdapter();
}

void main() {
  setUpAll(registerDefaultItemAttributes);

  const world = 'minecraft:overworld';

  group('ItemFilterApi', () {
    setUp(() => ItemFilterApiAdapter.wire = _wire);
    test('a create:filter holding X matches X and rejects Y', () {
      final api = _api();
      final filter = _listFilter([LStack.of('minecraft:stone')]);
      expect(api.testItem(world, filter, 'minecraft:stone'), isTrue);
      expect(api.testItem(world, filter, 'minecraft:dirt'), isFalse);
    });

    test('an empty filter slot matches everything', () {
      final api = _api();
      const empty = FilterItemValue('minecraft:air', count: 0);
      expect(empty.isEmpty, isTrue);
      expect(api.testItem(world, empty, 'minecraft:stone'), isTrue);
      expect(api.testItem(world, empty, 'create:cogwheel'), isTrue);
      expect(api.testFluid(world, empty, 'minecraft:water'), isTrue);
    });

    test('a freshly crafted create:filter is a plain stack and matches itself', () {
      // `FilterItemStack.of`: an empty component patch means Java keeps the plain wrapper
      // (`FilterItemStack.java:27-34`), so the filter matches the same item, not everything.
      final api = _api();
      const fresh = FilterItemValue.key(FilterItemKeys.list);
      expect(api.testItem(world, fresh, FilterItemKeys.list), isTrue);
      expect(api.testItem(world, fresh, 'minecraft:stone'), isFalse);
    });

    test('a blacklist list filter inverts', () {
      final api = _api();
      final filter = _listFilter(
        [LStack.of('minecraft:stone')],
        blacklist: true,
      );
      expect(api.testItem(world, filter, 'minecraft:stone'), isFalse);
      expect(api.testItem(world, filter, 'minecraft:dirt'), isTrue);
    });

    test('a list filter without filter items is an empty whitelist', () {
      final api = _api();
      // `ListFilterItemStack`: the flags are only read with the component present, so a list
      // filter that holds nothing matches nothing.
      const noContents = FilterItemValue(
        FilterItemKeys.list,
        components: [(FilterComponents.blacklist, [1])],
      );
      expect(api.testItem(world, noContents, 'minecraft:stone'), isFalse);
    });

    test('respectNbt gates the component match of the entries', () {
      final api = _api();
      // `minecraft:damage` (a varint), so the patch codec can read the value back.
      final named = LStack(
        'minecraft:stone',
        1,
        comps: {'minecraft:damage': base64Encode(const [1])},
      );
      final loose = _listFilter([named]);
      final strict = _listFilter([named], respectNbt: true);
      expect(api.testItem(world, loose, 'minecraft:stone'), isTrue);
      expect(api.testItem(world, strict, 'minecraft:stone'), isFalse);
    });

    test('a fluid filter resolves the fluid of the filter item', () {
      // Java's `resolveFluid` empties the filter item through `GenericItemEmptying`; the filter
      // part installs that lookup as `FilterItemStack.filterFluid` (world-free here).
      final previous = FilterItemStack.filterFluid;
      FilterItemStack.filterFluid = (stack) =>
          stack.key == 'minecraft:water_bucket' ? 'minecraft:water' : null;
      addTearDown(() => FilterItemStack.filterFluid = previous);

      final api = _api();
      const bucket = FilterItemValue.key('minecraft:water_bucket');
      expect(api.testFluid(world, bucket, 'minecraft:water'), isTrue);
      expect(api.testFluid(world, bucket, 'minecraft:lava'), isFalse);
      expect(
        api.testFluid(world, const FilterItemValue.key('minecraft:stone'), 'minecraft:water'),
        isFalse,
      );
    });
  });

  group('the provider', () {
    late CreateServices services;

    setUp(() {
      services = CreateServices();
      ItemFilterApiAdapter.wire = _wire;
    });

    tearDown(() {
      ItemAttributeHooks.itemInGroup = (_, _) => false;
    });

    test('the logistics module provides the ItemFilterApi', () {
      // `installLogisticsServices` is what `LogisticsModule.onLoad` runs; a server without the
      // module leaves the service absent and the consumers deny filter items.
      expect(services.find<ItemFilterApi>(), isNull);
      installLogisticsServices(services);
      final api = services.find<ItemFilterApi>();
      expect(api, isA<ItemFilterApiAdapter>());
      expect(
        api!.testItem(world, const FilterItemValue.key(FilterItemKeys.list), FilterItemKeys.list),
        isTrue,
      );
      expect(() => installLogisticsServices(services), throwsStateError);
    });

    test('in_item_group reads the creative tabs of the manifest', () {
      installLogisticsServices(services);
      expect(ItemAttributeHooks.itemInGroup('create:cogwheel', 'create:base'), isTrue);
      expect(ItemAttributeHooks.itemInGroup('create:cogwheel', 'create:palettes'), isFalse);
      // Palette blocks are in the palettes tab only.
      expect(ItemAttributeHooks.itemInGroup('create:metal_girder', 'create:palettes'), isTrue);
      expect(ItemAttributeHooks.itemInGroup('create:metal_girder', 'create:base'), isFalse);
      // `AllCreativeModeTabs` excludes the shopping list from both tabs.
      expect(ItemAttributeHooks.itemInGroup('create:shopping_list', 'create:base'), isFalse);
      // `PackageStyles.RARE_BOXES` join the exclusion predicate.
      expect(ItemAttributeHooks.itemInGroup('create:rare_creeper_package', 'create:base'), isFalse);
      // Vanilla tabs and items are not part of the manifest.
      expect(ItemAttributeHooks.itemInGroup('minecraft:stone', 'create:base'), isFalse);
      expect(ItemAttributeHooks.itemInGroup('create:cogwheel', 'minecraft:building_blocks'), isFalse);
    });

    test('the attribute filter offers the creative tabs of a stack', () {
      installLogisticsServices(services);
      final attributes = ItemAttributeRegistry.instance
          .typeOf('in_item_group')!
          .attributesOf(LStack.of('create:cogwheel'))
          .cast<InItemGroupAttribute>();
      expect(attributes.map((a) => a.group), ['create:base']);
      expect(attributes.single.appliesTo(LStack.of('create:cogwheel')), isTrue);
      expect(attributes.single.appliesTo(LStack.of('minecraft:stone')), isFalse);
    });
  });

  group('the conveyance filter slot', () {
    late ItemFilterApi api;

    setUp(() => api = _api());
    tearDown(() => filtering.itemFilterApi = () => null);

    test('a filter item is matched through the provider', () {
      filtering.itemFilterApi = () => api;
      expect(filtering.isFilterItemKey(FilterItemKeys.list), isTrue);
      final loose = ItemValue(
        FilterItemKeys.list,
        1,
        comps: _listFilter([LStack.of('minecraft:stone')]).components,
      );
      expect(filtering.filterTest(loose, ItemValue('minecraft:stone', 1), worldId: world), isTrue);
      expect(filtering.filterTest(loose, ItemValue('minecraft:dirt', 1), worldId: world), isFalse);
    });

    test('without a provider a filter item matches nothing', () {
      filtering.itemFilterApi = () => null;
      final filter = ItemValue(FilterItemKeys.list, 1);
      expect(filtering.filterTest(filter, ItemValue('minecraft:stone', 1), worldId: world), isFalse);
    });

    test('an empty slot and a plain item still match directly', () {
      filtering.itemFilterApi = () => null;
      expect(
        filtering.filterTest(ItemValue.empty, ItemValue('minecraft:stone', 1), worldId: world),
        isTrue,
      );
      expect(
        filtering.filterTest(ItemValue('minecraft:stone', 1), ItemValue('minecraft:stone', 1), worldId: world),
        isTrue,
      );
      expect(
        filtering.filterTest(ItemValue('minecraft:stone', 1), ItemValue('minecraft:dirt', 1), worldId: world),
        isFalse,
      );
    });
  });
}
