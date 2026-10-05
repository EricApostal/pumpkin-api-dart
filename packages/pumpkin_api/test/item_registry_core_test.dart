import 'package:pumpkin_api/src/item_registry_core.dart';
import 'package:test/test.dart';

final class _Fake implements ItemRegistryBackend {
  final List<String> vanilla;
  final registered = <RegisteredItem>[];

  _Fake(this.vanilla);

  @override
  int register(ItemRegistration item) {
    final id = vanilla.length + registered.length;
    registered.add(RegisteredItem(item.key, id));
    return id;
  }

  @override
  void registerTag(String tag, List<String> entries) {}

  @override
  int? idOf(String key) => null;

  @override
  String? keyOf(int id) => null;

  @override
  int get vanillaCount => vanilla.length;

  @override
  List<RegisteredItem> get vanillaItems => [
    for (var i = 0; i < vanilla.length; i++) RegisteredItem(vanilla[i], i),
  ];

  @override
  List<RegisteredItem> get registeredItems => registered;
}

void main() {
  const keys = ['minecraft:air', 'minecraft:stone', 'minecraft:granite'];

  group('checkVanillaItems', () {
    test('accepts the expected list', () {
      ItemRegistryChecks.checkVanillaItems(_Fake(keys), keys);
    });

    test('fails on a different count and names both numbers', () {
      expect(
        () => ItemRegistryChecks.checkVanillaItems(_Fake(keys.sublist(1)), keys),
        throwsA(
          isA<ItemRegistryException>().having(
            (e) => e.message,
            'message',
            allOf(contains('has 2 vanilla items'), contains('for 3')),
          ),
        ),
      );
    });

    test('fails on the first different key', () {
      final other = [...keys]..[2] = 'minecraft:diorite';
      expect(
        () => ItemRegistryChecks.checkVanillaItems(_Fake(other), keys),
        throwsA(
          isA<ItemRegistryException>().having(
            (e) => e.message,
            'message',
            contains('Vanilla item 2 is `minecraft:diorite`'),
          ),
        ),
      );
    });
  });

  group('checkAssignedIds', () {
    test('accepts vanillaCount + index', () {
      ItemRegistryChecks.checkAssignedIds(
        vanillaCount: 3,
        assigned: const [RegisteredItem('a:x', 3), RegisteredItem('a:y', 4)],
      );
    });

    test('fails when another plugin registered first', () {
      expect(
        () => ItemRegistryChecks.checkAssignedIds(
          vanillaCount: 3,
          assigned: const [RegisteredItem('a:x', 5)],
        ),
        throwsA(
          isA<ItemRegistryException>().having(
            (e) => e.message,
            'message',
            contains('Another plugin'),
          ),
        ),
      );
    });
  });

  test('key validation follows the host rules', () {
    expect(ItemRegistryChecks.isValidKey('lonsdaleite:refined_lonsdaleite'), isTrue);
    expect(ItemRegistryChecks.isValidKey('a:b/c.d-e'), isTrue);
    expect(ItemRegistryChecks.isValidKey('minecraft:x'), isFalse);
    expect(ItemRegistryChecks.isValidKey('nonamespace'), isFalse);
    expect(ItemRegistryChecks.isValidKey('A:b'), isFalse);
    expect(ItemRegistryChecks.isValidKey('a:'), isFalse);
    expect(ItemRegistryChecks.isValidKey('a/b:c'), isFalse);
  });
}
