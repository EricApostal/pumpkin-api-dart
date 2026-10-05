/// The content manifest (`data/manifest.json`) as Dart classes.
library;

import 'dart:convert';

import 'components.dart';

export 'components.dart' show Json;

Json _obj(Object? value) => value! as Json;

/// The `mod` block.
final class ModInfo {
  final String id;
  final String name;
  final String version;
  final String license;
  final String minecraftVersion;
  final String neoforgeVersion;

  /// The git commit of the sources the manifest was generated from.
  final String? sourceCommit;

  const ModInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.license,
    required this.minecraftVersion,
    required this.neoforgeVersion,
    this.sourceCommit,
  });

  factory ModInfo.fromJson(Json json) => ModInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    version: json['version']! as String,
    license: json['license']! as String,
    minecraftVersion: json['minecraft_version']! as String,
    neoforgeVersion: json['neoforge_version']! as String,
    sourceCommit: json['source_commit'] as String?,
  );
}

/// A question the generator could not settle from the mod's sources.
final class OpenQuestion {
  final String id;
  final String text;

  const OpenQuestion(this.id, this.text);
}

/// A `ToolMaterial`.
final class ToolMaterialInfo {
  final String incorrectBlocksForDrops;
  final int durability;
  final double speed;
  final double attackDamageBonus;
  final int enchantmentValue;
  final String repairItems;

  const ToolMaterialInfo({
    required this.incorrectBlocksForDrops,
    required this.durability,
    required this.speed,
    required this.attackDamageBonus,
    required this.enchantmentValue,
    required this.repairItems,
  });

  factory ToolMaterialInfo.fromJson(Json json) => ToolMaterialInfo(
    incorrectBlocksForDrops: json['incorrect_blocks_for_drops']! as String,
    durability: json['durability']! as int,
    speed: (json['speed']! as num).toDouble(),
    attackDamageBonus: (json['attack_damage_bonus']! as num).toDouble(),
    enchantmentValue: json['enchantment_value']! as int,
    repairItems: json['repair_items']! as String,
  );
}

/// An `ArmorMaterial`.
final class ArmorMaterialInfo {
  final int durability;

  /// Defence points by slot name (`helmet`, `chestplate`, `leggings`, `boots`).
  final Map<String, int> defense;
  final int enchantmentValue;
  final String equipSound;
  final double toughness;
  final double knockbackResistance;
  final String repairItems;
  final String assetId;

  const ArmorMaterialInfo({
    required this.durability,
    required this.defense,
    required this.enchantmentValue,
    required this.equipSound,
    required this.toughness,
    required this.knockbackResistance,
    required this.repairItems,
    required this.assetId,
  });

  factory ArmorMaterialInfo.fromJson(Json json) => ArmorMaterialInfo(
    durability: json['durability']! as int,
    defense: {
      for (final e in (json['defense']! as Json).entries)
        e.key: e.value! as int,
    },
    enchantmentValue: json['enchantment_value']! as int,
    equipSound: json['equip_sound']! as String,
    toughness: (json['toughness']! as num).toDouble(),
    knockbackResistance: (json['knockback_resistance']! as num).toDouble(),
    repairItems: json['repair_items']! as String,
    assetId: json['asset_id']! as String,
  );
}

/// The kinds of item, from the Java class and builder that created it.
enum ItemKind {
  material('material'),
  pickaxe('pickaxe'),
  axe('axe'),
  shovel('shovel'),
  hoe('hoe'),
  omnitool('omnitool'),
  sword('sword'),
  shortSword('short_sword'),
  warAxe('war_axe'),
  spear('spear'),
  mace('mace'),
  armor('armor'),
  blockItem('block_item');

  /// The name in the manifest.
  final String wireName;

  const ItemKind(this.wireName);

  static ItemKind parse(String name) => values.firstWhere(
    (k) => k.wireName == name,
    orElse: () => throw FormatException('Unknown item kind `$name`'),
  );
}

/// One item of the mod.
final class ManifestItem {
  /// `lonsdaleite:lonsdaleite_pickaxe`.
  final String id;

  /// Position in the mod's registration order.
  final int registrationIndex;
  final ItemKind kind;

  /// The material constant (`lonsdaleite`, `perfect_lonsdaleite`), if any.
  final String? tier;
  final String translationKey;
  final String displayName;

  /// The Java class and what it overrides.
  final String javaClass;
  final List<String> javaOverrides;

  /// Ids of the [Behavior]s that apply to this item.
  final List<String> behaviors;

  /// The default components the mod's Java builders produce (what the client
  /// computes too).
  final ItemComponents components;

  /// Components only the server needs to differ in, to emulate Java overrides.
  final Json serverComponents;

  /// The block this item places, for the block item.
  final String? block;

  const ManifestItem({
    required this.id,
    required this.registrationIndex,
    required this.kind,
    required this.tier,
    required this.translationKey,
    required this.displayName,
    required this.javaClass,
    required this.javaOverrides,
    required this.behaviors,
    required this.components,
    required this.serverComponents,
    required this.block,
  });

  factory ManifestItem.fromJson(Json json) {
    final java = json['java']! as Json;
    return ManifestItem(
      id: json['id']! as String,
      registrationIndex: json['registration_index']! as int,
      kind: ItemKind.parse(json['kind']! as String),
      tier: json['tier'] as String?,
      translationKey: json['translation_key']! as String,
      displayName: json['display_name']! as String,
      javaClass: java['class']! as String,
      javaOverrides: [
        for (final o in java['overrides']! as List<Object?>) o! as String,
      ],
      behaviors: [
        for (final b in json['behaviors']! as List<Object?>) b! as String,
      ],
      components: ItemComponents(json['components']! as Json),
      serverComponents: (json['server_components'] as Json?) ?? const {},
      block: json['block'] as String?,
    );
  }

  /// The components the server registers: the mod's, with the server-only
  /// replacements applied.
  ItemComponents get serverView => components.merged(serverComponents);

  /// The id without the namespace.
  String get path => id.substring(id.indexOf(':') + 1);
}

/// The wardframe block.
final class ManifestBlock {
  final String id;
  final String translationKey;
  final double destroyTime;
  final double explosionResistance;
  final String soundType;
  final bool canOcclude;
  final bool requiresCorrectToolForDrops;
  final int lightLevel;

  /// Vanilla `isSuffocating`: false for the wardframe, so a player who walks
  /// through it is not hurt.
  final bool isSuffocating;

  /// Vanilla `replaceable()` (a block placed against it replaces it).
  final bool replaceable;

  /// The shape of the block when no entity asks (`full_cube`). The mod lets
  /// players, tamed pets and mounts with a player through (`collision.empty_for`),
  /// which a server cannot model per entity.
  final String collisionDefault;

  /// The boolean state properties, in the order the Java class declares them.
  final List<String> properties;

  /// Their default values.
  final Map<String, bool> defaults;

  /// The properties in the order that numbers the states: sorted by name,
  /// the first most significant (`block_state.state_order`).
  final List<String> stateOrder;

  /// The state count (2^properties).
  final int stateCount;

  /// Every state by index (`block_state.states`): the value of each property.
  final List<Map<String, bool>> states;

  /// The state that placing the block starts from.
  final int defaultStateIndex;
  final String? lootTable;
  final List<String> blockTags;
  final List<String> itemTags;

  /// The item that places the block.
  final String item;

  const ManifestBlock({
    required this.id,
    required this.translationKey,
    required this.destroyTime,
    required this.explosionResistance,
    required this.soundType,
    required this.canOcclude,
    required this.requiresCorrectToolForDrops,
    required this.lightLevel,
    required this.isSuffocating,
    required this.replaceable,
    required this.collisionDefault,
    required this.properties,
    required this.defaults,
    required this.stateOrder,
    required this.stateCount,
    required this.states,
    required this.defaultStateIndex,
    required this.lootTable,
    required this.blockTags,
    required this.itemTags,
    required this.item,
  });

  factory ManifestBlock.fromJson(Json json) {
    final props = json['properties']! as Json;
    final state = json['block_state']! as Json;
    final tags = json['tags']! as Json;
    return ManifestBlock(
      id: json['id']! as String,
      translationKey: json['translation_key']! as String,
      destroyTime: (props['destroy_time']! as num).toDouble(),
      explosionResistance: (props['explosion_resistance']! as num).toDouble(),
      soundType: props['sound_type']! as String,
      canOcclude: props['can_occlude']! as bool,
      requiresCorrectToolForDrops:
          props['requires_correct_tool_for_drops']! as bool,
      lightLevel: props['light_level']! as int,
      isSuffocating: props['is_suffocating']! as bool,
      replaceable: (json['vanilla_defaults']! as Json)['replaceable']! as bool,
      collisionDefault: (json['collision']! as Json)['default']! as String,
      properties: [
        for (final p in state['declaration_order']! as List<Object?>)
          p! as String,
      ],
      defaults: {
        for (final e in (state['properties']! as Json).entries)
          e.key: (e.value! as Json)['default']! as bool,
      },
      stateOrder: [
        for (final p in state['state_order']! as List<Object?>) p! as String,
      ],
      stateCount: state['state_count']! as int,
      states: [
        for (final entry in state['states']! as List<Object?>)
          {
            for (final e in ((entry! as Json)['properties']! as Json).entries)
              e.key: e.value! as bool,
          },
      ],
      defaultStateIndex: state['default_state_index']! as int,
      lootTable: json['loot_table'] as String?,
      blockTags: [
        for (final t in tags['block']! as List<Object?>) t! as String,
      ],
      itemTags: [for (final t in tags['item']! as List<Object?>) t! as String],
      item: json['item']! as String,
    );
  }
}

/// The mod's creative tab and where it adds items to vanilla tabs.
final class CreativeTabs {
  final String id;
  final String titleKey;
  final String icon;

  /// Items in display order.
  final List<String> items;
  final List<TabInsertion> insertions;

  const CreativeTabs({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.items,
    required this.insertions,
  });

  factory CreativeTabs.fromJson(Json json) {
    final own = json['own']! as Json;
    return CreativeTabs(
      id: own['id']! as String,
      titleKey: own['title_key']! as String,
      icon: own['icon']! as String,
      items: [for (final i in own['items']! as List<Object?>) i! as String],
      insertions: [
        for (final i in json['insertions']! as List<Object?>)
          TabInsertion.fromJson(i! as Json),
      ],
    );
  }
}

/// `insertAfter(anchor, item)` in a vanilla creative tab.
final class TabInsertion {
  final String tab;
  final String after;
  final String item;
  final String visibility;

  const TabInsertion({
    required this.tab,
    required this.after,
    required this.item,
    required this.visibility,
  });

  factory TabInsertion.fromJson(Json json) => TabInsertion(
    tab: json['tab']! as String,
    after: json['after']! as String,
    item: json['item']! as String,
    visibility: json['visibility']! as String,
  );
}

/// A tag file: `values` are ids or `#tag` references.
final class TagFile {
  final String id;
  final bool replace;
  final List<String> values;

  const TagFile({
    required this.id,
    required this.replace,
    required this.values,
  });

  factory TagFile.fromJson(String id, Json json) => TagFile(
    id: id,
    replace: (json['replace'] as bool?) ?? false,
    values: [for (final v in json['values']! as List<Object?>) v! as String],
  );
}

/// A recipe file.
final class Recipe {
  final String id;
  final String type;
  final Json json;

  const Recipe(this.id, this.type, this.json);

  /// The result item.
  String get result => (json['result']! as Json)['id']! as String;

  /// The result count.
  int get resultCount => (json['result']! as Json)['count']! as int;

  /// Every ingredient (an id or a `#tag`), without duplicates.
  Set<String> get ingredients {
    final out = <String>{};
    void add(Object? value) {
      switch (value) {
        case final String s:
          out.add(s);
        case final List<Object?> l:
          l.forEach(add);
        default:
          throw FormatException('Unsupported ingredient in $id: $value');
      }
    }

    final key = json['key'];
    if (key != null) {
      (key as Json).values.forEach(add);
    }
    if (json.containsKey('ingredient')) add(json['ingredient']);
    return out;
  }
}

/// A loot table file.
final class LootTable {
  final String id;
  final Json json;

  const LootTable(this.id, this.json);

  /// Item ids the entries drop.
  Set<String> get items {
    final out = <String>{};
    void walk(Object? node) {
      switch (node) {
        case final Json m:
          if (m['type'] == 'minecraft:item' && m['name'] is String) {
            out.add(m['name']! as String);
          }
          m.values.forEach(walk);
        case final List<Object?> l:
          l.forEach(walk);
      }
    }

    walk(json);
    return out;
  }
}

/// Server-side or client-side behaviour that the mod's Java implements.
final class Behavior {
  final String id;

  /// `server`, `client` or `both`.
  final String side;
  final List<String> targets;
  final String summary;

  const Behavior({
    required this.id,
    required this.side,
    required this.targets,
    required this.summary,
  });

  factory Behavior.fromJson(Json json) => Behavior(
    id: json['id']! as String,
    side: json['side']! as String,
    targets: [for (final t in json['targets']! as List<Object?>) t! as String],
    summary: json['summary']! as String,
  );
}

/// Everything the mod adds.
final class Manifest {
  final int schemaVersion;
  final ModInfo mod;
  final List<OpenQuestion> openQuestions;
  final Map<String, ToolMaterialInfo> toolMaterials;
  final Map<String, ArmorMaterialInfo> armorMaterials;
  final List<ManifestItem> items;
  final ManifestBlock block;
  final CreativeTabs creativeTabs;

  /// `item` and `block` tags: registry to tag id to file.
  final Map<String, Map<String, TagFile>> tags;
  final List<Recipe> recipes;
  final List<LootTable> lootTables;
  final List<Behavior> behaviors;

  /// English translations by key.
  final Map<String, String> lang;

  const Manifest({
    required this.schemaVersion,
    required this.mod,
    required this.openQuestions,
    required this.toolMaterials,
    required this.armorMaterials,
    required this.items,
    required this.block,
    required this.creativeTabs,
    required this.tags,
    required this.recipes,
    required this.lootTables,
    required this.behaviors,
    required this.lang,
  });

  /// Parses the manifest JSON text.
  factory Manifest.parse(String source) =>
      Manifest.fromJson(jsonDecode(source) as Json);

  factory Manifest.fromJson(Json json) {
    final materials = json['materials']! as Json;
    final tags = json['tags']! as Json;
    final recipes = json['recipes']! as Json;
    return Manifest(
      schemaVersion: json['schema_version']! as int,
      mod: ModInfo.fromJson(json['mod']! as Json),
      openQuestions: [
        for (final q in json['open_questions']! as List<Object?>)
          OpenQuestion(_obj(q)['id']! as String, _obj(q)['text']! as String),
      ],
      toolMaterials: {
        for (final e in (materials['tool']! as Json).entries)
          e.key: ToolMaterialInfo.fromJson(e.value! as Json),
      },
      armorMaterials: {
        for (final e in (materials['armor']! as Json).entries)
          e.key: ArmorMaterialInfo.fromJson(e.value! as Json),
      },
      items: [
        for (final i in json['items']! as List<Object?>)
          ManifestItem.fromJson(i! as Json),
      ],
      block: ManifestBlock.fromJson(json['block']! as Json),
      creativeTabs: CreativeTabs.fromJson(json['creative_tabs']! as Json),
      tags: {
        for (final registry in tags.entries)
          registry.key: {
            for (final t in (registry.value! as Json).entries)
              t.key: TagFile.fromJson(t.key, t.value! as Json),
          },
      },
      recipes: [
        for (final r in recipes['entries']! as List<Object?>)
          Recipe(
            _obj(r)['id']! as String,
            _obj(r)['type']! as String,
            _obj(r)['json']! as Json,
          ),
      ],
      lootTables: [
        for (final t in json['loot_tables']! as List<Object?>)
          LootTable(_obj(t)['id']! as String, _obj(t)['json']! as Json),
      ],
      behaviors: [
        for (final b in json['behaviors']! as List<Object?>)
          Behavior.fromJson(b! as Json),
      ],
      lang: {
        for (final e in (json['lang']! as Json).entries)
          e.key: e.value! as String,
      },
    );
  }

  /// The item called [id], or `null`.
  ManifestItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Items of one [kind].
  Iterable<ManifestItem> itemsOfKind(ItemKind kind) =>
      items.where((i) => i.kind == kind);
}
