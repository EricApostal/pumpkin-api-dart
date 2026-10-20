import 'dart:convert';
import 'dart:math';

import 'package:create/src/core/nbt.dart';
import 'package:create/src/logistics/filter/filter_item_stack.dart';
import 'package:create/src/logistics/filter/item_attribute.dart';
import 'package:create/src/logistics/model/inventory.dart';
import 'package:create/src/logistics/model/orders.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_wire.dart';
import 'package:create/src/logistics/packager/repackager/repackage_helper.dart';
import 'package:create/src/logistics/packager/unpacking.dart';
import 'package:create/src/logistics/requester/auto_request_data.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketBuffer, VanillaIds;
import 'package:test/test.dart';

LStack stackWithComponent(
  String key,
  String component,
  List<int> bytes, {
  int count = 1,
}) => LStack(key, count, comps: {component: base64Encode(bytes)});

void main() {
  setUpAll(registerDefaultItemAttributes);

  group('package addresses', () {
    test('exact, wildcard and glob matches', () {
      expect(PackageItem.matchAddress('main', 'main'), isTrue);
      expect(PackageItem.matchAddress('main', 'other'), isFalse);
      expect(PackageItem.matchAddress('*', 'anything'), isTrue);
      expect(PackageItem.matchAddress('factory/*', 'factory/a'), isTrue);
      expect(PackageItem.matchAddress('factory/*', 'shop/a'), isFalse);
      expect(PackageItem.matchAddress('', '  '), isTrue);
    });

    test('packages round trip their contents', () {
      final box = PackageItem.containingList([
        LStack.of('minecraft:stone', 10),
        LStack.of('minecraft:iron_ingot', 3),
      ]);
      expect(PackageItem.isPackage(box), isTrue);
      final contents = PackageItem.contentsList(box);
      expect(
        contents.map((s) => s.key),
        containsAll(['minecraft:stone', 'minecraft:iron_ingot']),
      );
      expect(contents.firstWhere((s) => s.key == 'minecraft:stone').count, 10);
    });
  });

  group('filters', () {
    test(
      'an empty filter matches everything and a plain filter the same item',
      () {
        expect(
          FilterItemStack.empty.test(LStack.of('minecraft:stone')),
          isTrue,
        );

        final filter = FilterItemStack.of(LStack.of('minecraft:stone'));
        expect(filter.test(LStack.of('minecraft:stone', 12)), isTrue);
        expect(filter.test(LStack.of('minecraft:dirt')), isFalse);
      },
    );

    test('a package filter matches by address', () {
      final filterStack = PackageItem.addAddress(
        LStack.of(FilterItemKeys.package),
        'factory/*',
      );
      final filter = FilterItemStack.of(filterStack);
      expect(filter.isFilterItem, isTrue);

      final matching = PackageItem.addAddress(
        PackageStyles.defaultBox(),
        'factory/1',
      );
      final other = PackageItem.addAddress(
        PackageStyles.defaultBox(),
        'shop/1',
      );
      expect(filter.test(matching), isTrue);
      expect(filter.test(other), isFalse);
    });

    test('an attribute filter applies its whitelist mode', () {
      final entries = jsonEncode([
        {
          'attribute': {'type': 'has_name', 'value': 'Special'},
          'inverted': false,
        },
      ]);
      final customData = NetworkNbt.encode(
        NbtValue.compound({
          FilterComponents.privateAttributes: NbtValue.string(entries),
        }),
      );
      final filterStack = stackWithComponent(
        FilterItemKeys.attribute,
        'minecraft:custom_data',
        customData,
      );
      final filter =
          FilterItemStack.of(filterStack) as AttributeFilterItemStack;

      expect(filter.attributeTests, hasLength(1));
      final named = stackWithComponent(
        'minecraft:stone',
        'minecraft:custom_name',
        // `ComponentSerialization.STREAM_CODEC`: a network NBT text component, not a string.
        NetworkNbt.encode(
          NbtValue.compound({'text': NbtValue.string('Special')}),
        ),
      );
      final unnamed = LStack.of('minecraft:stone');
      expect(filter.test(named), isTrue);
      expect(filter.test(unnamed), isFalse);
    });

    test('a list filter reads the encoded ghost slots', () {
      final wire = StackWire(
        items: ItemIdResolver.vanilla(),
        componentIdOf: (_) => null,
        componentNameOf: (_) => null,
      );
      final contents = PacketBuffer.encode(
        (w) => wire.writeContents(w, [
          LStack.of('minecraft:stone', 5),
          LStack.empty,
        ]),
      );
      LStack listFilter({required bool blacklist}) => LStack(
        FilterItemKeys.list,
        1,
        comps: {
          FilterComponents.filterItems: base64Encode(contents),
          FilterComponents.respectNbt: base64Encode([0]),
          FilterComponents.blacklist: base64Encode([blacklist ? 1 : 0]),
        },
      );

      final filter = FilterItemStack.of(
        listFilter(blacklist: false),
        wire: wire,
      );
      expect(filter, isA<ListFilterItemStack>());
      expect(filter.test(LStack.of('minecraft:stone', 1)), isTrue);
      expect(filter.test(LStack.of('minecraft:dirt')), isFalse);

      final blacklisted = FilterItemStack.of(
        listFilter(blacklist: true),
        wire: wire,
      );
      expect((blacklisted as ListFilterItemStack).isBlacklist, isTrue);
      expect(blacklisted.test(LStack.of('minecraft:stone')), isFalse);
      expect(blacklisted.test(LStack.of('minecraft:dirt')), isTrue);
    });

    test('attribute dispatch values parse from the client NBT form', () {
      final inTag = ItemAttributeRegistry.instance.attributeFromMap({
        'type': 'create:in_tag',
        'value': '#minecraft:logs',
      });
      expect(inTag, isA<InTagAttribute>());
      expect((inTag! as InTagAttribute).tag, 'minecraft:logs');

      final shulker = ItemAttributeRegistry.instance.attributeFromMap({
        'type': 'create:shulker_fill_level',
        'value': 'partial',
      });
      expect(shulker, isA<ShulkerFillLevelAttribute>());
      expect((shulker! as ShulkerFillLevelAttribute).level, 1);

      final singleton = ItemAttributeRegistry.instance.attributeFromMap({
        'type': 'create:placeable',
      });
      expect(singleton, isA<SingletonAttribute>());
    });

    test('a blacklist attribute filter matches everything else', () {
      final entries = jsonEncode([
        {
          'attribute': {'type': 'has_name', 'value': 'Special'},
          'inverted': false,
        },
      ]);
      final customData = NetworkNbt.encode(
        NbtValue.compound({
          FilterComponents.privateAttributes: NbtValue.string(entries),
        }),
      );
      final filterStack = stackWithComponent(
        FilterItemKeys.attribute,
        'minecraft:custom_data',
        customData,
        count: 1,
      ).withComp('create:attribute_filter_whitelist_mode', [2]);
      final filter =
          FilterItemStack.of(filterStack) as AttributeFilterItemStack;
      expect(filter.whitelistMode, AttributeFilterWhitelistMode.blacklist);
      expect(filter.test(LStack.of('minecraft:stone')), isTrue);
    });

    test('a list filter without filter items matches nothing', () {
      // Java only reads the flags when the component is present: an empty filter is an empty
      // whitelist, not a blacklist.
      final empty = FilterItemStack.of(
        LStack(FilterItemKeys.list, 1, comps: const {'minecraft:custom_name': ''}),
      ) as ListFilterItemStack;
      expect(empty.isBlacklist, isFalse);
      expect(empty.test(LStack.of('minecraft:stone')), isFalse);
    });

    test('a freshly crafted filter is a plain stack', () {
      final fresh = FilterItemStack.of(LStack.of(FilterItemKeys.list));
      expect(fresh, isA<FilterItemStack>());
      expect(fresh.isFilterItem, isFalse);
      expect(fresh.test(LStack.of(FilterItemKeys.list)), isTrue);
    });

    test('attributes read the component values Java reads', () {
      final registry = ItemAttributeRegistry.instance;

      // `has_color`: the `dye` component (a varint colour id).
      final dyed = stackWithComponent(
        'minecraft:wool',
        'minecraft:dye',
        [14],
      );
      final colors = registry
          .typeOf('has_color')!
          .attributesOf(dyed)
          .cast<ColorAttribute>();
      expect(colors.map((c) => c.color), ['red']);
      expect(colors.single.appliesTo(dyed), isTrue);
      expect(colors.single.translationKey, 'color');

      // `has_color`: the item key prefix (Java's `RegisteredObjectsHelper` path check).
      final namedColor = registry
          .typeOf('has_color')!
          .attributesOf(LStack.of('minecraft:light_blue_wool'))
          .cast<ColorAttribute>();
      expect(namedColor.map((c) => c.color), ['light_blue']);

      // `has_enchant`: `enchantments` is a map of registry id -> level.
      final sharpness = VanillaIds.enchantments.idOf('sharpness')!;
      final enchanted = stackWithComponent(
        'minecraft:diamond_sword',
        'minecraft:enchantments',
        [1, sharpness, 5],
      );
      final enchants = registry
          .typeOf('has_enchant')!
          .attributesOf(enchanted)
          .cast<EnchantAttribute>();
      expect(enchants.map((e) => e.enchantment), ['minecraft:sharpness']);
      expect(enchants.single.appliesTo(enchanted), isTrue);
      expect(
        const EnchantAttribute('minecraft:unbreaking').appliesTo(enchanted),
        isFalse,
      );

      // `book_copy`: the generation is an int, the key names the copy.
      final book = stackWithComponent(
        'minecraft:written_book',
        'minecraft:written_book_content',
        [
          ...utf8.encode('\x04Test'), // title (Filterable<String> raw)
          0, // no filtered title
          ...utf8.encode('\x06Author'),
          2, // generation
          0, // no pages
          0, // not resolved
        ],
      );
      final copies = registry
          .typeOf('book_copy')!
          .attributesOf(book)
          .cast<BookCopyAttribute>();
      expect(copies.single.generation, 2);
      expect(copies.single.translationKey, 'book_copy_second');
      expect(
        registry.attributeFromMap({'type': 'create:book_copy', 'value': 2}),
        isA<BookCopyAttribute>(),
      );

      final authors = registry
          .typeOf('book_author')!
          .attributesOf(book)
          .cast<BookAuthorAttribute>();
      expect(authors.single.author, 'Author');

      // `equipable`: only a slot of another type than HAND (0 mainhand, 1 offhand).
      final helmet = stackWithComponent(
        'minecraft:iron_helmet',
        'minecraft:equippable',
        [5],
      );
      expect(registry.typeOf('placeable')!.attributesOf(helmet), isEmpty);
      expect(
        registry.typeOf('equipable')!.attributesOf(helmet),
        hasLength(1),
      );
      final inHand = stackWithComponent(
        'minecraft:stick',
        'minecraft:equippable',
        [0],
      );
      expect(registry.typeOf('equipable')!.attributesOf(inHand), isEmpty);

      // `shulker_fill_level` is keyed by its enum name and named `shulker_level`.
      final shulker = ShulkerFillLevelAttribute(1);
      expect(shulker.key, 'partial');
      expect(shulker.value, 'partial');
      expect(shulker.translationKey, 'shulker_level');

      // `in_tag` writes the tag with its `#`.
      expect(const InTagAttribute('minecraft:logs').value, '#minecraft:logs');
    });
  });

  group('unpacking', () {
    test('the default handler simulates and inserts', () async {
      final target = MemoryInv(2);
      final items = [LStack.of('minecraft:stone', 70)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(
          target,
          items,
          simulate: true,
        ),
        isTrue,
      );
      expect(target.nonEmpty(), isEmpty);

      final toInsert = [LStack.of('minecraft:stone', 70)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(
          target,
          toInsert,
          simulate: false,
        ),
        isTrue,
      );
      expect(target.at(0).count + target.at(1).count, 70);
    });

    test('a full inventory fails the simulation', () async {
      final target = MemoryInv(1);
      target.set(0, LStack.of('minecraft:dirt', 64));
      final items = [LStack.of('minecraft:stone', 1)];
      expect(
        await UnpackingHandlers.defaultHandler.unpack(
          target,
          items,
          simulate: true,
        ),
        isFalse,
      );
    });

    test('the creative crate voids the contents', () async {
      expect(
        UnpackingHandlers.of('create:creative_crate'),
        same(UnpackingHandlers.voiding),
      );
    });
  });

  group('repackaging', () {
    LStack fragment(
      int orderId,
      int linkIndex,
      int fragmentIndex, {
      required bool finalLink,
      required bool isFinal,
      required List<LStack> contents,
    }) {
      final box = PackageItem.containingList(contents);
      return PackageItem.setOrder(
        box,
        orderId,
        linkIndex,
        finalLink,
        fragmentIndex,
        isFinal,
        null,
      );
    }

    test('an incomplete order is not repacked', () {
      final helper = PackageRepackageHelper();
      final box = fragment(
        7,
        0,
        0,
        finalLink: false,
        isFinal: false,
        contents: [LStack.of('minecraft:stone', 5)],
      );
      expect(helper.addPackageFragment(box), -1);
    });

    test('a complete order is combined', () {
      final helper = PackageRepackageHelper();
      final box = fragment(
        7,
        0,
        0,
        finalLink: true,
        isFinal: true,
        contents: [LStack.of('minecraft:stone', 5)],
      );
      expect(PackageItem.getOrderId(box), 7);
      expect(PackageItem.orderData(box)?.isFinal, isTrue);
      expect(helper.addPackageFragment(box), 7);
      expect(helper.isOrderComplete(7), isTrue);

      final exported = helper.repack(7, _FixedRandom());
      expect(exported, hasLength(1));
      expect(PackageItem.getOrderId(exported.first.stack), 7);
      final contents = PackageItem.contentsList(exported.first.stack);
      expect(contents.single.key, 'minecraft:stone');
      expect(contents.single.count, 5);
    });
  });

  group('auto request data', () {
    test('the offset is made relative to the placed block', () {
      final data = AutoRequestData(
        PackageOrderWithCrafts.empty(),
        'main',
        (10, 64, 10),
        'minecraft:overworld',
        true,
      );
      final read = data.readFromItem((4, 64, 4), 'minecraft:overworld');
      expect(read.targetOffset, (6, 0, 6));
      expect(read.isValid, isTrue);
      expect(read.targetPos((4, 64, 4)), (10, 64, 10));

      final otherDimension = data.readFromItem((
        4,
        64,
        4,
      ), 'minecraft:the_nether');
      expect(otherDimension.isValid, isFalse);
    });
  });

  group('inventory summary', () {
    test('counts and corrections', () {
      final summary = InventorySummary();
      summary.add(LStack.of('minecraft:stone', 10), 10);
      summary.add(LStack.of('minecraft:stone', 1), 5);
      expect(summary.countOf(LStack.of('minecraft:stone')), 15);
      summary.add(LStack.of('minecraft:stone', 1), -4);
      expect(summary.countOf(LStack.of('minecraft:stone')), 11);
    });
  });
}

/// A deterministic random for the repack test.
final class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
