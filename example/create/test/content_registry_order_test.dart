// The canonical id order (`content/canonical_registry_order.dart`) is what keeps the plugin's
// numeric registry ids equal to the Java mod's. It is built from the content manifest, so this
// test can load it on the plain VM (the `CreateRegistry` itself imports the host API).
//
// It checks that every id-bearing registry has a list, that no list has a duplicate (a duplicate
// would be dropped when the order is installed), and that the declarative registrations the
// modules derive from pure data are covered by the orders they belong to. The parts of a module
// that touch the host (the block builders, the recipe list, ...) are asserted at runtime by the
// `OrderReport` loop in `plugin/create_plugin.dart`, which runs before `applyRegistry`.
import 'package:create/src/content/canonical_registry_order.dart';
import 'package:create/src/content/components.dart';
import 'package:create/src/content/material_content.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:test/test.dart';

/// The `RegistryKind` values that carry a host id, by name. Kept as strings so this file stays
/// off the host API; `applyCanonicalOrder` maps them back with `RegistryKind.values.byName`.
const Set<String> idBearingKinds = {
  'items',
  'blocks',
  'blockEntityTypes',
  'menus',
  'dataComponents',
  'fluids',
  'entityTypes',
  'damageTypes',
  'sounds',
  'particles',
  'recipeTypes',
  'mobEffects',
};

void main() {
  final order = canonicalRegistryOrder();
  // The block and item manifests carry an explicit index across the merged Java classes.
  final blocks = [...kBlocks]..sort((a, b) => a.index.compareTo(b.index));
  final items = [...kItems]..sort((a, b) => a.index.compareTo(b.index));

  test('every id-bearing registry kind has a canonical order', () {
    expect(order.keys.toSet(), idBearingKinds);
  });

  test('no canonical list has a duplicate key', () {
    for (final entry in order.entries) {
      final seen = <String>{};
      for (final key in entry.value) {
        expect(
          seen.add(key),
          isTrue,
          reason: 'duplicate `$key` in the canonical ${entry.key} order',
        );
      }
    }
  });

  test('canonical keys are namespaced and non-empty', () {
    for (final entry in order.entries) {
      for (final key in entry.value) {
        expect(key, startsWith('create:'), reason: '${entry.key}: $key');
        expect(key.length, greaterThan('create:'.length), reason: entry.key);
      }
    }
  });

  test('block and item orders follow the manifest indices', () {
    expect(order['blocks'], [for (final b in blocks) 'create:${b.key}']);
    expect(order['items'], [for (final i in items) 'create:${i.key}']);
  });

  test('each fluid is listed with its source before its flowing variant', () {
    final fluids = order['fluids']!;
    for (final def in kFluids) {
      final source = 'create:${def.sourceKey}';
      final flowing = 'create:${def.flowingKey}';
      expect(fluids, contains(source), reason: def.key);
      expect(fluids, contains(flowing), reason: def.key);
      expect(
        fluids.indexOf(source),
        lessThan(fluids.indexOf(flowing)),
        reason: def.key,
      );
    }
  });

  test('the sound order lists every registered event of every entry', () {
    expect(order['sounds'], [
      for (final s in kSoundEvents)
        for (final e in s.registeredEvents) 'create:$e',
    ]);
  });

  test('the recipe type order skips the vanilla-backed types', () {
    final recipeTypes = order['recipeTypes']!;
    expect(recipeTypes, [for (final t in CreateRecipeType.registered) t.key]);
    expect(recipeTypes, isNot(contains('create:toolbox_dyeing')));
    expect(recipeTypes, isNot(contains('create:item_copying')));
  });

  test(
    'the module registrations from pure data are all in their canonical list',
    () {
      void covered(String kind, Iterable<String> keys) {
        final canonical = order[kind]!.toSet();
        for (final key in keys) {
          expect(
            canonical,
            contains(key),
            reason: '$kind: `$key` is not in the canonical order',
          );
        }
      }

      // `content.material_content` (registered by the content module).
      covered('items', materialItemKeys.map((k) => 'create:$k'));
      covered('blocks', materialBlockKeys.map((k) => 'create:$k'));
      // `content.components` (the data components of `AllDataComponents`).
      covered('dataComponents', createComponents.map((c) => c.key));
      // The global registries the content module declares from the manifest.
      covered('menus', kMenuTypes.map((m) => 'create:${m.key}'));
      covered('damageTypes', kDamageTypes.map((d) => 'create:${d.key}'));
      covered('particles', kParticleTypes.map((p) => 'create:${p.key}'));
      // `logistics.package` (the 14 package styles of `PackageStyles`).
      covered('items', PackageStyles.allKeys);
      // `processing.recipe_type` (the recipe types of `AllRecipeTypes`).
      covered('recipeTypes', CreateRecipeType.registered.map((t) => t.key));
      // Entity types are all manifest keys registered by several modules.
      covered('entityTypes', kEntityTypes.map((e) => 'create:${e.key}'));
    },
  );

  test('the canonical counts match the Java registries', () {
    // Counts from `blocks.g.dart`, `items.g.dart` and `registries.g.dart`; a change here means the
    // manifest changed and the canonical order has to be re-checked against the Java tree.
    expect(order['blocks'], hasLength(643));
    expect(order['items'], hasLength(699));
    expect(order['blockEntityTypes'], hasLength(114));
    expect(order['entityTypes'], hasLength(9));
    expect(order['menus'], hasLength(14));
    expect(order['dataComponents'], hasLength(57));
    expect(order['fluids'], hasLength(4 * 2)); // source + flowing per fluid
    expect(order['damageTypes'], hasLength(9));
    expect(
      order['sounds'],
      hasLength(79),
    ); // main events plus the `_compounded_n` ones
    expect(order['particles'], hasLength(13));
    expect(order['recipeTypes'], hasLength(17));
    expect(order['mobEffects'], isEmpty);
  });
}
