// The canonical id order of every id-bearing registry, built from the content manifest.
//
// This is the host-free half of `manifest/canonical_order.dart`: the manifest lists are the Java
// registration order, and `applyCanonicalOrder` installs these key lists on the `CreateRegistry`.
// Keeping the lists in a file that only imports the manifest lets `dart test` check them on the
// plain VM (the registry itself imports the host API and cannot be loaded there).
//
// The map keys are the `RegistryKind` names. `applyCanonicalOrder` maps them back, and throws if a
// kind has no order here, so a new id-bearing kind cannot be added without deciding its order.
import '../manifest/blocks.g.dart';
import '../manifest/items.g.dart';
import '../manifest/registries.g.dart';

/// The canonical keys of every id-bearing registry, in Java registration order.
///
/// Keys are full registry keys (`create:cogwheel`). A list with no entries is a registry Create
/// does not populate (`mobEffects`), not a missing order.
Map<String, List<String>> canonicalRegistryOrder() {
  // The manifest carries an explicit `index` for blocks and items because their extraction merges
  // several Java classes; the other lists are already stored in registration order.
  final blocks = [...kBlocks]..sort((a, b) => a.index.compareTo(b.index));
  final items = [...kItems]..sort((a, b) => a.index.compareTo(b.index));

  return {
    'items': [for (final i in items) 'create:${i.key}'],
    'blocks': [for (final b in blocks) 'create:${b.key}'],
    'blockEntityTypes': [for (final e in kBlockEntityTypes) 'create:${e.key}'],
    'menus': [for (final m in kMenuTypes) 'create:${m.key}'],
    'dataComponents': [for (final c in kDataComponents) 'create:${c.key}'],
    // Registrate registers the source fluid before its flowing variant.
    'fluids': [
      for (final f in kFluids) ...[
        'create:${f.sourceKey}',
        'create:${f.flowingKey}',
      ],
    ],
    'entityTypes': [for (final e in kEntityTypes) 'create:${e.key}'],
    'damageTypes': [for (final d in kDamageTypes) 'create:${d.key}'],
    // A sound event entry can register several events (`<key>_compounded_<i>`).
    'sounds': [
      for (final s in kSoundEvents)
        for (final e in s.registeredEvents) 'create:$e',
    ],
    'particles': [for (final p in kParticleTypes) 'create:${p.key}'],
    // `toolbox_dyeing` and `item_copying` reuse vanilla recipe types; only the others are numbered.
    'recipeTypes': [
      for (final r in kRecipeTypes)
        if (r.registersRecipeType) 'create:${r.key}',
    ],
    // Create registers no mob effect; the empty list documents that and makes any future one show
    // up as an `extra` in the order report.
    'mobEffects': const [],
  };
}
