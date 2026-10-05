/// Turns the parsed mod ([ModSource], [ModData]) into the manifest JSON.
library;

import 'dart:io';

import 'java_text.dart';
import 'mod_data.dart';
import 'mod_source.dart';
import 'vanilla.dart';

/// Bumped when the manifest's shape changes.
const manifestSchemaVersion = 1;

/// What the server has to do for each `@Override` the mod's classes declare,
/// keyed by method name. Every override found in the Java must be listed, so
/// a mod update that adds one fails the generation instead of going unnoticed.
const _overrideCatalog = <String, _OverrideInfo>{
  'mineBlock': _OverrideInfo(
    id: 'tool.mine_block_durability',
    side: 'server',
    summary:
        'Pickaxe classes: after a block with non-zero hardness is mined on the '
        'server, hurtAndBreak(1). The Tool component\'s damage_per_block already '
        'does this (1 by default) in vanilla\'s Item.mineBlock, so the override '
        'is believed redundant.',
  ),
  'hurtEnemy': _OverrideInfo(
    id: 'weapon.hurt_enemy_durability',
    side: 'server',
    summary:
        'Sword, dagger and war axe classes: hurtAndBreak(1) when an enemy is '
        'hurt. Vanilla also charges the Weapon component\'s item_damage_per_attack '
        '(1) per attack, so these items may lose 2 durability per hit. Unverified.',
  ),
  'isCorrectToolForDrops': _OverrideInfo(
    id: 'omnitool.is_correct_tool_for_drops',
    side: 'both',
    summary:
        'ORs Items.NETHERITE_{PICKAXE,AXE,SHOVEL,HOE,SWORD}.isCorrectToolForDrops(stack, state). '
        'The stack passed is the omnitool\'s own, and the vanilla implementation '
        'reads the stack\'s Tool component, so this is believed to equal the '
        'omnitool\'s own Tool rules (the pickaxe rules). Unverified.',
  ),
  'getDestroySpeed': _OverrideInfo(
    id: 'omnitool.destroy_speed',
    side: 'both',
    summary:
        'Mining speed is the material speed on any block in the pickaxe, axe, '
        'shovel or hoe mineable tags or #minecraft:sword_efficient, else 1.0. '
        'The Tool component alone (pickaxe rules) gives it only on pickaxe blocks.',
  ),
  'useOn': _OverrideInfo(
    id: 'omnitool.use_on',
    side: 'server',
    summary:
        'Right click on a block: tries the vanilla axe, then (hoe, shovel; '
        'swapped while sneaking) block transformers on the held stack, and '
        'damages it like the dedicated tools.',
  ),
  'appendHoverText': _OverrideInfo(
    id: 'block_item.tooltip',
    side: 'client',
    summary: 'Two grey tooltip lines on the wardframe item. Client only.',
  ),
  'getStateForPlacement': _OverrideInfo(
    id: 'wardframe.placement_state',
    side: 'server',
    summary:
        'A placed wardframe sets each of its six face properties to whether '
        'that neighbour is a wardframe.',
  ),
  'updateShape': _OverrideInfo(
    id: 'wardframe.update_shape',
    side: 'server',
    summary:
        'When a neighbour changes, the face property of that direction is '
        'recomputed (true when the neighbour is a wardframe).',
  ),
  'getCollisionShape': _OverrideInfo(
    id: 'wardframe.collision',
    side: 'server',
    summary:
        'Per entity: empty shape for players, tamed TamableAnimals and any '
        'entity with a player passenger; a full cube for everything else and '
        'for queries without an entity (pathfinding).',
  ),
  'isPathfindable': _OverrideInfo(
    id: 'wardframe.pathfinding',
    side: 'server',
    summary: 'Never pathfindable: mobs treat every wardframe as a wall.',
  ),
  'createBlockStateDefinition': _OverrideInfo(
    id: 'wardframe.state_definition',
    side: 'both',
    summary: 'Six boolean properties north, south, east, west, up, down.',
  ),
};

final class _OverrideInfo {
  final String id;
  final String side;
  final String summary;

  const _OverrideInfo({required this.id, required this.side, required this.summary});
}

/// Questions the generator cannot answer from the sources it reads. They are
/// part of the manifest so the consumers see them.
const _openQuestions = <Json>[
  {
    'id': 'builders-observed',
    'text':
        'The component values of Item.Properties#pickaxe/axe/shovel/hoe/sword/spear/'
        'humanoidArmor are modelled from the vanilla 26.3 items in Pumpkin\'s '
        'assets/items.json (an extractor dump), not from decompiled source. '
        '`generate_manifest.dart --verify-vanilla` re-checks the model against '
        'every vanilla tool, spear and armor piece of the tiers it knows.',
  },
  {
    'id': 'weapon-double-wear',
    'text':
        'The sword, dagger and war axe classes override hurtEnemy with '
        'hurtAndBreak(1). If vanilla 26.3 also applies the Weapon component\'s '
        'item_damage_per_attack (1) after a hit, those items lose 2 durability per '
        'hit. Not verified against the decompiled game.',
  },
  {
    'id': 'omnitool-correct-tool',
    'text':
        'Whether Items.NETHERITE_*.isCorrectToolForDrops(omnitoolStack, state) uses '
        'the passed stack\'s Tool component (then the override equals the pickaxe '
        'rules) or the netherite item\'s own is not verified.',
  },
  {
    'id': 'spear-sounds',
    'text':
        'Spears of non-wooden materials get the default spear sounds '
        '(item.spear.*); only the wooden tier differs in vanilla.',
  },
  {
    'id': 'block-defaults',
    'text':
        'Block properties the mod does not set (friction, speed/jump factor, '
        'map colour, instrument, push reaction) are the BlockBehaviour.Properties.of() '
        'defaults and are not parsed; vanilla_defaults lists the ones that were assumed.',
  },
  {
    'id': 'no-fire-resistance',
    'text':
        'None of the mod\'s items call fireResistant(), so unlike netherite '
        'gear they carry no minecraft:damage_resistant component and burn in lava.',
  },
  {
    'id': 'registry-ids',
    'text':
        'Items and the block are listed in registration order; with NeoForge\'s '
        'DeferredRegister that order decides the numeric ids after the vanilla ones. '
        'The id mapping actually used must come from the registry sync, not from here.',
  },
];

/// Everything the manifest holds.
Json buildManifest({
  required ModSource source,
  required ModData data,
  required Json modInfo,
}) {
  final materials = source.materials;
  final items = source.items;
  final block = source.block;

  final behaviorItems = <String, Set<String>>{};
  void note(String method, String target) {
    final info = _overrideCatalog[method];
    if (info == null) {
      throw JavaParseError('Override `$method` on $target is not in the behaviour catalogue');
    }
    (behaviorItems[info.id] ??= {}).add(target);
  }

  final itemJson = <Json>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final behaviors = <String>[];
    for (final method in item.overrides) {
      note(method, item.id);
      behaviors.add(_overrideCatalog[method]!.id);
    }
    if (item.javaSuper == 'MaceItem') {
      (behaviorItems['mace.smash_attack'] ??= {}).add(item.id);
      behaviors.add('mace.smash_attack');
    }

    final nameKey = ((item.components['minecraft:item_name']! as Json)['translate']) as String;
    final displayName = data.lang[nameKey];
    if (displayName == null) throw JavaParseError('No translation for $nameKey');

    final entry = <String, Object?>{
      'id': item.id,
      'registration_index': index,
      'java_field': item.field,
      'kind': _kind(item),
      'tier': item.toolMaterial?.toLowerCase() ?? item.armorMaterial?.toLowerCase(),
      'max_stack_size': item.components['minecraft:max_stack_size'],
      'translation_key': nameKey,
      'display_name': displayName,
      'java': {
        'class': item.javaClass,
        'extends': item.javaSuper,
        'overrides': item.overrides,
        'builder_calls': item.builderCalls,
      },
      'behaviors': behaviors,
      'components': item.components,
    };
    if (item.overrides.contains('getDestroySpeed')) {
      entry['server_components'] = _omnitoolServerComponents(source, item);
    }
    if (item.javaSuper == 'BlockItem') entry['block'] = block.id;
    itemJson.add(entry);
  }

  final blockItems = items.where((i) => i.id == block.id && i.javaSuper == 'BlockItem');
  if (blockItems.length != 1) {
    throw JavaParseError('Expected exactly one block item for ${block.id}');
  }
  for (final method in block.overrides) {
    note(method, block.id);
  }

  return {
    'schema_version': manifestSchemaVersion,
    'generator': 'example/lonsdaleite/tool/generate_manifest.dart',
    'mod': modInfo,
    'open_questions': _openQuestions,
    'materials': {
      'tool': {
        for (final e in materials.tools.entries) e.key.toLowerCase(): e.value.toJson(),
      },
      'armor': {
        for (final e in materials.armor.entries) e.key.toLowerCase(): e.value.toJson(),
      },
    },
    'items': itemJson,
    'block': _blockJson(block, data),
    'creative_tabs': {
      'own': {
        'id': source.ownTab.id,
        'title_key': source.ownTab.titleKey,
        'title': data.lang[source.ownTab.titleKey],
        'icon': source.ownTab.icon,
        'items': source.ownTab.items,
      },
      'insertions': [
        for (final i in source.tabInsertions)
          {
            'tab': i.tab,
            'after': i.after,
            'item': i.item,
            'visibility': i.visibility,
          },
      ],
    },
    'tags': {
      for (final registry in data.tags.keys.toList()..sort())
        registry: {
          for (final id in data.tags[registry]!.keys.toList()..sort())
            id: data.tags[registry]![id],
        },
    },
    'recipes': {
      'types': _countBy(data.recipes, (r) => r['type']! as String),
      'entries': data.recipes,
    },
    'loot_tables': data.lootTables,
    'behaviors': [
      for (final entry in behaviorItems.entries)
        _behaviorJson(entry.key, entry.value),
    ]..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String)),
    'lang': data.lang,
    'client': {
      'resource_pack': data.assets,
      'pack_meta': data.packMeta,
      'unread_data_files': data.unreadDataFiles,
    },
  };
}

Json _behaviorJson(String id, Set<String> targets) {
  final info = _overrideCatalog.values.where((i) => i.id == id).firstOrNull;
  if (info != null) {
    return {
      'id': id,
      'side': info.side,
      'targets': targets.toList()..sort(),
      'summary': info.summary,
    };
  }
  if (id == 'mace.smash_attack') {
    return {
      'id': id,
      'side': 'server',
      'targets': targets.toList()..sort(),
      'summary':
          'The class extends vanilla MaceItem, which gives it the smash attack '
          '(fall distance above 1.5, bonus damage, knockback and sounds). '
          'It overrides nothing itself.',
    };
  }
  throw JavaParseError('Unknown behaviour $id');
}

String _kind(ItemRegistration item) {
  if (item.javaSuper == 'BlockItem') return 'block_item';
  final c = item.javaClass;
  if (c.contains('Omnitool')) return 'omnitool';
  if (c.contains('Short_Sword')) return 'short_sword';
  if (c.contains('War_Axe')) return 'war_axe';
  if (c.contains('Mace')) return 'mace';
  if (item.armorMaterial != null) return 'armor';
  final first = item.builderCalls.isEmpty ? null : item.builderCalls.first.split('(').first;
  return switch (first) {
    'pickaxe' => 'pickaxe',
    'axe' => 'axe',
    'shovel' => 'shovel',
    'hoe' => 'hoe',
    'sword' => 'sword',
    'spear' => 'spear',
    null => 'material',
    final other => throw JavaParseError('Cannot classify ${item.id} (builder $other)'),
  };
}

Map<String, int> _countBy(List<Json> list, String Function(Json) key) {
  final counts = <String, int>{};
  for (final e in list) {
    counts.update(key(e), (n) => n + 1, ifAbsent: () => 1);
  }
  return Map.fromEntries(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// The omnitool's mining speed override as Tool component rules, which is the
/// form Pumpkin reads: the stack's own rules followed by the speed of
/// every other mineable tag. These components are for the server only; clients
/// keep computing the same speed in Java.
Json _omnitoolServerComponents(ModSource source, ItemRegistration item) {
  final body = source.methodBody(item.javaClass, 'getDestroySpeed');
  final tags = [
    for (final m in RegExp(r'BlockTags\.(\w+)').allMatches(body))
      switch (m.group(1)!) {
        final n when n.startsWith('MINEABLE_WITH_') =>
          'minecraft:mineable/${n.substring('MINEABLE_WITH_'.length).toLowerCase()}',
        final n => 'minecraft:${n.toLowerCase()}',
      },
  ];
  if (!body.contains('getMiningSpeed(this.material)') || !body.contains('return 1.0F;')) {
    throw JavaParseError('Unexpected getDestroySpeed body in ${item.javaClass}');
  }
  final tool = item.components['minecraft:tool']! as Json;
  final rules = (tool['rules']! as List<Object?>).cast<Json>();
  final speed = rules.firstWhere((r) => r['speed'] != null)['speed'];
  final seen = {for (final r in rules) r['blocks'] as String};
  return {
    'minecraft:tool': {
      ...tool,
      'rules': [
        ...rules,
        for (final tag in tags)
          if (!seen.contains('#$tag')) {'blocks': '#$tag', 'speed': speed},
      ],
    },
  };
}

Json _blockJson(BlockRegistration block, ModData data) {
  final sorted = [...block.properties]..sort();
  final states = <Json>[];
  final count = 1 << sorted.length;
  // Vanilla numbers states with the alphabetically first property varying
  // slowest and `true` before `false`.
  for (var index = 0; index < count; index++) {
    final values = <String, bool>{
      for (var i = 0; i < sorted.length; i++)
        sorted[i]: ((index >> (sorted.length - 1 - i)) & 1) == 0,
    };
    states.add({'index': index, 'properties': values});
  }
  final defaultIndex = states.indexWhere((s) {
    final props = s['properties']! as Map<String, bool>;
    return sorted.every((p) => props[p] == block.defaults[p]);
  });

  final blockTags = <String>[
    for (final e in (data.tags['block'] ?? {}).entries)
      if ((e.value['values']! as List<Object?>).contains(block.id)) e.key,
  ];
  final itemTags = <String>[
    for (final e in (data.tags['item'] ?? {}).entries)
      if ((e.value['values']! as List<Object?>).contains(block.id)) e.key,
  ];
  final lootId = '${block.id.split(':').first}:blocks/${block.id.split(':').last}';
  final lootTable = data.lootTables.where((t) => t['id'] == lootId).firstOrNull;

  return {
    'id': block.id,
    'translation_key': 'block.${block.id.replaceFirst(':', '.')}',
    'java': {
      'class': block.javaClass,
      'extends': block.javaSuper,
      'overrides': block.overrides,
      'builder_calls': block.builderCalls,
    },
    'properties': {
      'destroy_time': block.destroyTime,
      'explosion_resistance': block.explosionResistance,
      'sound_type': block.soundType,
      'can_occlude': block.canOcclude,
      'requires_correct_tool_for_drops': block.requiresCorrectToolForDrops,
      'light_level': block.lightLevel,
      'is_suffocating': block.isSuffocating,
      'is_view_blocking': block.isViewBlocking,
    },
    'vanilla_defaults': {
      'friction': 0.6,
      'speed_factor': 1.0,
      'jump_factor': 1.0,
      'has_collision': true,
      'replaceable': false,
      'ignited_by_lava': false,
    },
    'block_state': {
      'declaration_order': block.properties,
      'state_order': sorted,
      'properties': {
        for (final p in block.properties) p: {'type': 'boolean', 'default': block.defaults[p]},
      },
      'state_count': count,
      'default_state_index': defaultIndex,
      'states': states,
    },
    'collision': {
      'default': 'full_cube',
      'empty_for': [
        'player',
        'tamed TamableAnimal',
        'entity with a player passenger',
      ],
      'solid_when_no_entity_context': true,
      'pathfindable': false,
    },
    'loot_table': lootTable == null ? null : lootId,
    'tags': {'block': blockTags, 'item': itemTags},
    'item': block.id,
  };
}

/// The `mod` block: ids and versions from the build files.
Json readModInfo(Directory root, String modId) {
  String? gradle(String key) {
    final m = RegExp('^$key=(.*)\$', multiLine: true)
        .firstMatch(File('${root.path}/gradle.properties').readAsStringSync());
    return m?.group(1)?.trim();
  }

  final toml = File('${root.path}/neoforge/src/main/resources/META-INF/neoforge.mods.toml')
      .readAsStringSync();
  String? tomlValue(String key) =>
      RegExp('^$key="([^"]*)"', multiLine: true).firstMatch(toml)?.group(1);

  String? commit;
  final head = File('${root.path}/.git/HEAD');
  if (head.existsSync()) {
    final result = Process.runSync('git', ['-C', root.path, 'rev-parse', 'HEAD']);
    if (result.exitCode == 0) commit = (result.stdout as String).trim();
  }
  return {
    'id': modId,
    'name': tomlValue('displayName'),
    'version': gradle('mod_version'),
    'license': tomlValue('license'),
    'minecraft_version': gradle('minecraft_version'),
    'neoforge_version': gradle('neoforge_version'),
    'source_commit': commit,
  };
}
