import 'package:lonsdaleite/src/item_install.dart';
import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart'
    show VanillaRegistries;
import 'package:test/test.dart';

final class _Backend implements ItemRegistryBackend {
  final List<String> vanilla;
  final int startOffset;
  final registeredList = <RegisteredItem>[];
  final registrations = <ItemRegistration>[];
  final tags = <String, List<String>>{};
  Map<String, int> readBackOverride = const {};

  _Backend(this.vanilla, {this.startOffset = 0});

  @override
  int register(ItemRegistration item) {
    registrations.add(item);
    final id = vanilla.length + startOffset + registeredList.length;
    registeredList.add(RegisteredItem(item.key, id));
    return id;
  }

  @override
  void registerTag(String tag, List<String> entries) => tags[tag] = entries;

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
  List<RegisteredItem> get registeredItems => [
    for (final e in registeredList)
      RegisteredItem(e.key, readBackOverride[e.key] ?? e.id),
  ];
}

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);
  final vanilla = VanillaRegistries.require('minecraft:item');

  test('the NeoForge spec assumes 1658 vanilla items', () {
    expect(vanilla, hasLength(1658));
  });

  test('registers 32 items in order with the ids vanillaCount + index', () {
    final backend = _Backend(vanilla);
    final installation = installManifestItems(
      manifest,
      BackendItemRegistrar(backend),
      expectedVanillaItems: vanilla,
    );
    expect(installation.vanillaCount, 1658);
    expect(installation.items, hasLength(32));
    expect(
      installation.items.first,
      const RegisteredItem('lonsdaleite:lonsdaleite_wardframe', 1658),
    );
    expect(
      installation.items.last,
      const RegisteredItem('lonsdaleite:perfect_lonsdaleite_boots', 1689),
    );
    expect(
      backend.registrations.map((r) => r.key),
      (manifest.items.toList()..sort(
            (a, b) => a.registrationIndex.compareTo(b.registrationIndex),
          ))
          .map((i) => i.id),
    );
    // Registered with the encoded components of the server view.
    final omnitool = backend.registrations.firstWhere(
      (r) => r.key == 'lonsdaleite:lonsdaleite_omnitool',
    );
    expect(omnitool.components.map((c) => c.name), contains('minecraft:tool'));
    expect(
      omnitool.components.map((c) => c.name),
      isNot(contains('minecraft:block_transformer')),
    );
  });

  test(
    'registers the 21 item tags (the block tags are registered with the block)',
    () {
      final backend = _Backend(vanilla);
      final installation = installManifestItems(
        manifest,
        BackendItemRegistrar(backend),
        expectedVanillaItems: vanilla,
      );
      expect(backend.tags, hasLength(21));
      expect(installation.itemTags, hasLength(21));
      expect(backend.tags['lonsdaleite:repairs_lonsdaleite_tools'], [
        'lonsdaleite:refined_lonsdaleite',
      ]);
      expect(backend.tags['minecraft:swords'], hasLength(6));
    },
  );

  test('records the skipped components', () {
    final installation = installManifestItems(
      manifest,
      BackendItemRegistrar(_Backend(vanilla)),
      expectedVanillaItems: vanilla,
    );
    expect(installation.skippedComponents.components, [
      'minecraft:block_transformer',
      'minecraft:interact_animation',
    ]);
  });

  test('fails loudly when the host has another vanilla item count', () {
    final short = vanilla.sublist(0, 1600);
    expect(
      () => installManifestItems(
        manifest,
        BackendItemRegistrar(_Backend(short)),
        expectedVanillaItems: vanilla,
      ),
      throwsA(
        isA<ItemRegistryException>().having(
          (e) => e.message,
          'message',
          allOf(contains('1600 vanilla items'), contains('for 1658')),
        ),
      ),
    );
  });

  test('registers nothing when the vanilla items differ', () {
    final backend = _Backend([...vanilla]..[10] = 'minecraft:something_else');
    expect(
      () => installManifestItems(
        manifest,
        BackendItemRegistrar(backend),
        expectedVanillaItems: vanilla,
      ),
      throwsA(isA<ItemRegistryException>()),
    );
    expect(backend.registrations, isEmpty);
  });

  test('fails when another plugin registered items first', () {
    expect(
      () => installManifestItems(
        manifest,
        BackendItemRegistrar(_Backend(vanilla, startOffset: 3)),
        expectedVanillaItems: vanilla,
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

  test('fails when the host reports other ids than it returned', () {
    final backend = _Backend(vanilla)
      ..readBackOverride = {'lonsdaleite:raw_lonsdaleite': 5000};
    expect(
      () => installManifestItems(
        manifest,
        BackendItemRegistrar(backend),
        expectedVanillaItems: vanilla,
      ),
      throwsA(
        isA<ItemRegistryException>().having(
          (e) => e.message,
          'message',
          contains('reports 5000'),
        ),
      ),
    );
  });
}
