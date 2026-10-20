// Applies a CreateRegistry to the host in the fixed order of ARCHITECTURE.md.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'block_entity.dart';
import 'perf.dart';
import 'registry.dart';
import 'shape_rule_checks.dart';

/// The ids the host assigned, by registry and key.
final class AppliedIds {
  final Map<RegistryKind, Map<String, int>> _ids = {
    for (final k in RegistryKind.values) k: {},
  };

  /// The host id of [key] in [kind], or `null`.
  int? of(RegistryKind kind, String key) => _ids[kind]![key];

  Map<String, int> all(RegistryKind kind) => Map.unmodifiable(_ids[kind]!);
}

/// Registers the content of [registry] with the host; call it from
/// `Plugin.onLoad` (registration closes when players can connect). Registries
/// that carry ids throw on failure; enchantments, advancements, recipe types
/// and commands are logged and skipped.
Future<AppliedIds> applyRegistry(
  CreateRegistry registry,
  Context host,
  BlockEntityStore store,
  Logger log, {
  bool logIds = false,
}) async {
  final ids = AppliedIds();

  void check(RegistryKind kind, String key, int id, int expected) {
    ids._ids[kind]![key] = id;
    if (logIds) log.info('${kind.name} $key = $id');
    if (id != expected) {
      log.warn(
        '`$key` got id $id in ${kind.name}, expected $expected: another plugin registered ${kind.name} first, '
        'so a NeoForge client would number it differently.',
      );
    }
  }

  // Items (block items are in the list already).
  final itemBase = ItemRegistries.host.vanillaCount;
  var n = 0;
  Perf.measure('applyRegistry.items', () {
    for (final e in registry.items.entries) {
      check(
        RegistryKind.items,
        e.key,
        ItemRegistries.host.register(e.value),
        itemBase + n++,
      );
    }
  });

  // Blocks, placement rules, block items.
  final blockBase = BlockRegistries.host.vanillaBlockCount;
  n = 0;
  final blocks = registry.blocks.entries;

  // The host validates shape rules and placement rules one block at a time and
  // stops at the first failure. Check all of them first so a single start names
  // every bad definition. `BlockDefinition.validate()` covers properties, shapes
  // and limits but not these two lists.
  Perf.measure('applyRegistry.blockValidation', () {
    for (final e in blocks) {
      final issues = <String>[
        ...e.value.definition.validate(),
        ...checkShapeRules(e.value.definition),
        ...checkPlacementRules(e.value),
      ];
      if (issues.isNotEmpty) {
        log.error(
          'Block `${e.key}` would be rejected by the host:\n  ${issues.join('\n  ')}',
        );
      }
    }
  });
  Perf.measure('applyRegistry.blocks', () {
    for (final e in blocks) {
      check(
        RegistryKind.blocks,
        e.key,
        BlockRegistries.host.register(e.value.definition),
        blockBase + n++,
      );
    }
  });
  Perf.measure('applyRegistry.blockLinks', () {
    // One host call that returns every registered block (vanilla included); measured on its own
    // because it dominates the label when the per-block loop is cheap.
    final registered = Perf.measure(
      'applyRegistry.blockLinks.registeredBlocks',
      () => {for (final b in BlockRegistries.host.registeredBlocks) b.key: b},
    );
    for (final e in blocks) {
      final block = e.value;
      final entry = registered[block.key];
      if (entry != null) {
        block.blockId = entry.id;
        block.baseStateId = entry.baseStateId;
      }
      if (block.placement.isNotEmpty)
        BlockPlacements.host.setRules(block.key, block.placement);
      final itemKey = block.itemKey;
      if (itemKey != null) BlockRegistries.host.setBlockItem(itemKey, block.key);
    }
  });

  // Block entity types.
  final beBase = BlockEntityRegistries.host.vanillaCount;
  n = 0;
  Perf.measure('applyRegistry.blockEntityTypes', () {
    for (final e in registry.blockEntityTypes.entries) {
      check(
        RegistryKind.blockEntityTypes,
        e.key,
        BlockEntityRegistries.host.register(e.key, e.value.validBlocks),
        beBase + n++,
      );
      store.registerType(e.value);
    }
    store.applyTicking();
  });

  // Menus and data components.
  final menuBase = MenuRegistries.host.vanillaCount;
  n = 0;
  for (final e in registry.menus.entries) {
    check(
      RegistryKind.menus,
      e.key,
      MenuRegistries.host.register(e.key),
      menuBase + n++,
    );
  }
  final componentBase = ComponentTypeRegistries.host.vanillaCount;
  n = 0;
  for (final e in registry.dataComponents.entries) {
    check(
      RegistryKind.dataComponents,
      e.key,
      ComponentTypeRegistries.host.register(
        e.key,
        persistent: e.value.persistent,
        codec: e.value.codec,
      ),
      componentBase + n++,
    );
  }

  // Fluids, entity types, damage types, sounds, particles, mob effects.
  n = 0;
  final fluidBase = FluidRegistries.vanillaCount;
  for (final e in registry.fluids.entries) {
    check(
      RegistryKind.fluids,
      e.key,
      FluidRegistries.register(e.value),
      fluidBase + n++,
    );
  }
  n = 0;
  final entityBase = EntityRegistries.vanillaCount;
  for (final e in registry.entityTypes.entries) {
    check(
      RegistryKind.entityTypes,
      e.key,
      EntityRegistries.register(e.value),
      entityBase + n++,
    );
  }
  n = 0;
  final damageBase = DamageTypeRegistries.vanillaCount;
  for (final e in registry.damageTypes.entries) {
    check(
      RegistryKind.damageTypes,
      e.key,
      DamageTypeRegistries.register(e.value),
      damageBase + n++,
    );
  }
  for (final e in registry.sounds.entries) {
    ids._ids[RegistryKind.sounds]![e.key] = ExtraRegistries.registerSound(
      e.value,
    );
  }
  for (final e in registry.particles.entries) {
    ids._ids[RegistryKind.particles]![e.key] = ExtraRegistries.registerParticle(
      e.value,
    );
  }
  for (final e in registry.mobEffects.entries) {
    ids._ids[RegistryKind.mobEffects]![e.key] =
        ExtraRegistries.registerMobEffect(e.value);
  }

  // Tags.
  Perf.measure('applyRegistry.tags', () {
    for (final kind in TagKind.values) {
      for (final e in registry.tags[kind]!.entries) {
        switch (kind) {
          case TagKind.block:
            BlockRegistries.host.registerTag(e.key, e.value);
          case TagKind.item:
            ItemRegistries.host.registerTag(e.key, e.value);
          case TagKind.fluid:
            FluidRegistries.registerTag(e.key, e.value);
          case TagKind.entityType:
            EntityRegistries.registerTag(e.key, e.value);
        }
      }
    }
  });

  // Plugin synced registries and datapack registries (ExtraRegistries).
  for (final spec in registry.syncedRegistries.entries.map((e) => e.value)) {
    ExtraRegistries.declareSyncedRegistry(spec.key);
    for (final entry in spec.entries) {
      ExtraRegistries.addSyncedEntry(spec.key, entry);
    }
  }
  for (final key in registry.datapackRegistries) {
    ExtraRegistries.declareDatapackRegistry(key);
  }
  for (final e in registry.datapackEntries) {
    ExtraRegistries.addDatapackEntry(e.registry, e.id, e.data);
  }

  // The rest is not id bearing: a failure is logged, the plugin keeps loading.
  Future<void> soft(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, s) {
      log.error('Registering $what failed', error: e, stackTrace: s);
    }
  }

  if (registry.recipeTypes.length > 0) {
    await soft('recipe types', () async {
      final manager = host.getServer().getRecipeManager();
      for (final e in registry.recipeTypes.entries) {
        manager.defineRecipeType(e.key);
      }
      host.declareSyncedRecipeTypes([
        for (final e in registry.recipeTypes.entries)
          if (e.value) e.key,
      ]);
    });
  }
  for (final enchantment in registry.enchantments) {
    await soft(
      'an enchantment',
      () => host.registerCustomEnchantment(enchantment),
    );
  }
  await soft('advancements', () async {
    for (final key in registry.criterionTriggers) {
      Advancements.registerTrigger(key);
    }
    for (final a in registry.advancements) {
      Advancements.register(a);
    }
    for (final e in registry.advancementJson.entries) {
      Advancements.registerJson(e.key, e.value);
    }
  });

  // Block behaviours need the blocks, commands the permissions.
  await Perf.measureAsync('applyRegistry.behaviors', () async {
    for (final e in blocks) {
      await soft('the behaviour of ${e.key}', () async {
        final behavior = e.value.buildBehavior(store);
        if (behavior != null) host.registerBlockBehavior(e.key, behavior);
      });
    }
  });
  for (final c in registry.commands) {
    await soft('the command /${c.name}', () async {
      host.command(
        c.name,
        c.build,
        description: c.description,
        aliases: c.aliases,
        permission: c.permission,
      );
    });
  }
  return ids;
}
