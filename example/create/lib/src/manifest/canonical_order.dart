// Canonical registration order for the id-bearing registries.
//
// A real Create client has its own registries built from the Java mod: the
// numeric ids it uses for blocks, items, block entity types, entities, menus,
// data components, fluids, damage types, sounds, particles and recipe types are
// the Java registration order. NeoForge syncs the plugin's entries on top of the
// vanilla ones, so the order here has to match the Java mod exactly.
//
// The content manifest (`blocks.g.dart`, `items.g.dart`, `registries.g.dart`)
// was extracted from that Java tree and preserves the order, so it is the source
// of truth. Modules still register declaratively in any order; this reorders
// what they registered before the registry is applied to the host.
import '../core/registry.dart';
import 'blocks.g.dart';
import 'items.g.dart';
import 'registries.g.dart';

/// Installs the Java registration order on every id-bearing registry.
void applyCanonicalOrder(CreateRegistry registry) {
  final blocks = [...kBlocks]..sort((a, b) => a.index.compareTo(b.index));
  registry.useOrder(RegistryKind.blocks, [
    for (final b in blocks) 'create:${b.key}',
  ]);

  final items = [...kItems]..sort((a, b) => a.index.compareTo(b.index));
  registry.useOrder(RegistryKind.items, [
    for (final i in items) 'create:${i.key}',
  ]);

  registry.useOrder(RegistryKind.blockEntityTypes, [
    for (final e in kBlockEntityTypes) 'create:${e.key}',
  ]);
  registry.useOrder(RegistryKind.entityTypes, [
    for (final e in kEntityTypes) 'create:${e.key}',
  ]);
  registry.useOrder(RegistryKind.menus, [
    for (final m in kMenuTypes) 'create:${m.key}',
  ]);
  registry.useOrder(RegistryKind.dataComponents, [
    for (final c in kDataComponents) 'create:${c.key}',
  ]);

  // Registrate registers the source fluid before its flowing variant.
  registry.useOrder(RegistryKind.fluids, [
    for (final f in kFluids) ...[
      'create:${f.sourceKey}',
      'create:${f.flowingKey}',
    ],
  ]);

  registry.useOrder(RegistryKind.damageTypes, [
    for (final d in kDamageTypes) 'create:${d.key}',
  ]);

  // A sound event entry can register several events (`<key>_compounded_<i>`).
  registry.useOrder(RegistryKind.sounds, [
    for (final s in kSoundEvents)
      for (final e in s.registeredEvents) 'create:$e',
  ]);

  registry.useOrder(RegistryKind.particles, [
    for (final p in kParticleTypes) 'create:${p.key}',
  ]);

  registry.useOrder(RegistryKind.recipeTypes, [
    for (final r in kRecipeTypes)
      if (r.registersRecipeType) 'create:${r.key}',
  ]);
}
