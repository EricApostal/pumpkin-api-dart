/// Consistency checks over a [Manifest]: every id and tag it refers to inside
/// the mod's namespace must exist, and the components must agree with the
/// materials they were built from.
library;

import 'block_definition.dart';
import 'components.dart' show ToolRule;
import 'manifest.dart';

/// Ids the manifest uses that belong to other namespaces (vanilla), for the
/// host to check against its registries.
final class ExternalReferences {
  /// Items (`minecraft:stick`).
  final Set<String> items;

  /// Item tags without `#` (`minecraft:axes`).
  final Set<String> itemTags;

  /// Block tags without `#` (`minecraft:mineable/pickaxe`).
  final Set<String> blockTags;

  /// Blocks (`minecraft:cobweb`).
  final Set<String> blocks;

  const ExternalReferences({
    required this.items,
    required this.itemTags,
    required this.blockTags,
    required this.blocks,
  });
}

/// Checks [manifest] and returns what is wrong, empty when it is consistent.
List<String> validateManifest(Manifest manifest) => _Validator(manifest).run();

/// The references of [manifest] to namespaces other than the mod's.
ExternalReferences externalReferences(Manifest manifest) =>
    _Validator(manifest).external();

final class _Validator {
  final Manifest m;
  final String ns;
  final List<String> issues = [];

  _Validator(this.m) : ns = m.mod.id;

  late final Set<String> itemIds = {for (final i in m.items) i.id};

  bool _own(String id) => id.startsWith('$ns:');

  String _bare(String reference) =>
      reference.startsWith('#') ? reference.substring(1) : reference;

  List<String> run() {
    _items();
    _block();
    _tags();
    _recipes();
    _lootTables();
    _tabs();
    _behaviors();
    return issues;
  }

  void _items() {
    final seen = <String>{};
    for (final (index, item) in m.items.indexed) {
      if (!seen.add(item.id)) issues.add('Duplicate item ${item.id}');
      if (!_own(item.id)) issues.add('${item.id} is not in the $ns namespace');
      if (item.registrationIndex != index) {
        issues.add(
          '${item.id} has registration index ${item.registrationIndex}, expected $index',
        );
      }
      if (item.components.raw['minecraft:item_model'] != item.id) {
        issues.add(
          '${item.id} has item_model ${item.components.raw['minecraft:item_model']}',
        );
      }
      if (m.lang[item.translationKey] != item.displayName) {
        issues.add(
          '${item.id}: translation ${item.translationKey} does not match its display name',
        );
      }
      final stack = item.components.maxStackSize;
      final damage = item.components.maxDamage;
      if (stack == null || stack < 1 || stack > 99) {
        issues.add('${item.id}: bad max_stack_size $stack');
      }
      if (damage != null && stack != 1) {
        issues.add('${item.id} is damageable but stacks to $stack');
      }
      _itemMaterial(item);
    }
  }

  void _itemMaterial(ManifestItem item) {
    final c = item.components;
    final tierName = item.tier;
    if (tierName == null) return;
    if (item.kind == ItemKind.armor) {
      final material = m.armorMaterials[tierName];
      final equippable = c.equippable;
      if (material == null || equippable == null) {
        issues.add(
          '${item.id}: no armor material `$tierName` or no equippable',
        );
        return;
      }
      final type = switch (equippable.slot) {
        'head' => ('helmet', 11),
        'chest' => ('chestplate', 16),
        'legs' => ('leggings', 15),
        'feet' => ('boots', 13),
        final other => throw FormatException('Unknown armor slot $other'),
      };
      if (c.maxDamage != material.durability * type.$2) {
        issues.add(
          '${item.id}: max_damage ${c.maxDamage} != ${material.durability} x ${type.$2}',
        );
      }
      final armor = c.modifier('minecraft:armor');
      if (armor?.amount != material.defense[type.$1]?.toDouble()) {
        issues.add(
          '${item.id}: armor ${armor?.amount} != ${material.defense[type.$1]}',
        );
      }
      if (equippable.assetId != material.assetId ||
          equippable.equipSound != material.equipSound) {
        issues.add('${item.id}: equippable does not match its material');
      }
      if (c.enchantable != material.enchantmentValue) {
        issues.add(
          '${item.id}: enchantable ${c.enchantable} != ${material.enchantmentValue}',
        );
      }
      if (c.repairable != material.repairItems) {
        issues.add(
          '${item.id}: repairable ${c.repairable} != ${material.repairItems}',
        );
      }
      return;
    }
    final material = m.toolMaterials[tierName];
    if (material == null) {
      issues.add('${item.id}: no tool material `$tierName`');
      return;
    }
    if (c.maxDamage != material.durability) {
      issues.add(
        '${item.id}: max_damage ${c.maxDamage} != ${material.durability}',
      );
    }
    if (c.repairable != material.repairItems) {
      issues.add(
        '${item.id}: repairable ${c.repairable} != ${material.repairItems}',
      );
    }
    if (c.enchantable != material.enchantmentValue) {
      issues.add(
        '${item.id}: enchantable ${c.enchantable} != ${material.enchantmentValue}',
      );
    }
  }

  void _block() {
    final b = m.block;
    if (b.stateCount != 1 << b.properties.length) {
      issues.add(
        '${b.id}: ${b.stateCount} states for ${b.properties.length} boolean properties',
      );
    }
    if (b.defaultStateIndex < 0 || b.defaultStateIndex >= b.stateCount) {
      issues.add(
        '${b.id}: default state index ${b.defaultStateIndex} out of range',
      );
    }
    final item = m.item(b.item);
    if (item == null || item.block != b.id) {
      issues.add('${b.id}: its item ${b.item} is missing or does not place it');
    }
    if (b.lootTable == null || !m.lootTables.any((t) => t.id == b.lootTable)) {
      issues.add('${b.id}: loot table ${b.lootTable} is missing');
    }
    try {
      final definition = blockDefinitionFor(m);
      issues.addAll([
        for (final issue in definition.validate()) '${b.id}: $issue',
        ...blockStateIssues(m),
      ]);
    } on StateError catch (e) {
      issues.add(e.message);
    }
    for (final tag in b.blockTags) {
      if (!(m.tags['block']?.containsKey(tag) ?? false)) {
        issues.add('${b.id}: block tag $tag is missing');
      }
    }
    for (final tag in b.itemTags) {
      if (!(m.tags['item']?.containsKey(tag) ?? false)) {
        issues.add('${b.id}: item tag $tag is missing');
      }
    }
  }

  /// Whether a tag exists in the mod's files (own namespace only).
  bool _hasTag(String registry, String id) =>
      m.tags[registry]?.containsKey(id) ?? false;

  void _tags() {
    for (final entry in m.tags.entries) {
      for (final tag in entry.value.values) {
        for (final value in tag.values) {
          if (value.startsWith('#')) {
            final ref = value.substring(1);
            if (_own(ref) && !_hasTag(entry.key, ref)) {
              issues.add(
                '${entry.key} tag ${tag.id} references the missing tag $value',
              );
            }
          } else if (entry.key == 'item' &&
              _own(value) &&
              !itemIds.contains(value)) {
            issues.add('item tag ${tag.id} lists the unknown item $value');
          } else if (entry.key == 'block' &&
              _own(value) &&
              value != m.block.id) {
            issues.add('block tag ${tag.id} lists the unknown block $value');
          }
        }
      }
    }
    // Tags that items point at (repairable) must exist when they are ours.
    for (final item in m.items) {
      final repair = item.components.repairable;
      if (repair != null &&
          repair.startsWith('#') &&
          _own(_bare(repair)) &&
          !_hasTag('item', _bare(repair))) {
        issues.add('${item.id}: repair tag $repair is missing');
      }
    }
  }

  void _recipes() {
    final ids = <String>{};
    for (final r in m.recipes) {
      if (!ids.add(r.id)) issues.add('Duplicate recipe ${r.id}');
      if (_own(r.result) && !itemIds.contains(r.result)) {
        issues.add('Recipe ${r.id} makes the unknown item ${r.result}');
      }
      for (final ingredient in r.ingredients) {
        if (ingredient.startsWith('#')) {
          if (_own(_bare(ingredient)) && !_hasTag('item', _bare(ingredient))) {
            issues.add('Recipe ${r.id} uses the missing tag $ingredient');
          }
        } else if (_own(ingredient) && !itemIds.contains(ingredient)) {
          issues.add('Recipe ${r.id} uses the unknown item $ingredient');
        }
      }
    }
    // Every craftable item has exactly one recipe except the raw chain's inputs.
    final made = <String, int>{};
    for (final r in m.recipes) {
      made.update(r.result, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final item in m.items) {
      if (made[item.id] == null) issues.add('${item.id} has no recipe');
      if ((made[item.id] ?? 0) > 1) {
        issues.add('${item.id} has several recipes');
      }
    }
  }

  void _lootTables() {
    for (final t in m.lootTables) {
      for (final item in t.items) {
        if (_own(item) && !itemIds.contains(item)) {
          issues.add('Loot table ${t.id} drops the unknown item $item');
        }
      }
    }
  }

  void _tabs() {
    final tab = m.creativeTabs;
    if (!itemIds.contains(tab.icon)) {
      issues.add('Creative tab icon ${tab.icon} is not an item');
    }
    if (!m.lang.containsKey(tab.titleKey)) {
      issues.add('Creative tab title ${tab.titleKey} has no translation');
    }
    final listed = <String>{};
    for (final id in tab.items) {
      if (!itemIds.contains(id)) {
        issues.add('Creative tab lists the unknown item $id');
      }
      if (!listed.add(id)) issues.add('Creative tab lists $id twice');
    }
    for (final id in itemIds.difference(listed)) {
      issues.add('Creative tab does not list $id');
    }
    final placed = <String>{};
    final chains = <String, Set<String>>{};
    for (final i in tab.insertions) {
      if (!itemIds.contains(i.item)) {
        issues.add('Insertion of the unknown item ${i.item}');
      }
      if (!placed.add('${i.tab}/${i.item}')) {
        issues.add('${i.item} inserted twice into ${i.tab}');
      }
      final known = chains.putIfAbsent(i.tab, () => {});
      // An anchor is either vanilla or an item inserted just before.
      if (_own(i.after) && !known.contains(i.after)) {
        issues.add(
          'Insertion of ${i.item} into ${i.tab} follows ${i.after}, which is not inserted before it',
        );
      }
      known.add(i.item);
    }
  }

  void _behaviors() {
    final known = {for (final b in m.behaviors) b.id};
    for (final item in m.items) {
      for (final id in item.behaviors) {
        if (!known.contains(id)) {
          issues.add('${item.id} refers to the unknown behaviour $id');
        }
      }
    }
    for (final b in m.behaviors) {
      for (final target in b.targets) {
        if (!itemIds.contains(target) && target != m.block.id) {
          issues.add('Behaviour ${b.id} targets the unknown $target');
        }
      }
    }
  }

  ExternalReferences external() {
    final items = <String>{};
    final itemTags = <String>{};
    final blockTags = <String>{};
    final blocks = <String>{};

    void item(String reference) {
      if (reference.startsWith('#')) {
        if (!_own(reference.substring(1))) itemTags.add(reference.substring(1));
      } else if (!_own(reference)) {
        items.add(reference);
      }
    }

    void blockRef(String reference) {
      if (reference.startsWith('#')) {
        if (!_own(reference.substring(1))) {
          blockTags.add(reference.substring(1));
        }
      } else if (!_own(reference)) {
        blocks.add(reference);
      }
    }

    for (final r in m.recipes) {
      r.ingredients.forEach(item);
      item(r.result);
    }
    for (final t in m.lootTables) {
      t.items.forEach(item);
    }
    for (final entry in m.tags.entries) {
      for (final tag in entry.value.values) {
        for (final v in tag.values) {
          if (entry.key == 'item') item(v);
          if (entry.key == 'block') blockRef(v);
        }
        // Tag files in other namespaces (minecraft:axes) extend vanilla tags.
        if (!_own(tag.id)) {
          (entry.key == 'item' ? itemTags : blockTags).add(tag.id);
        }
      }
    }
    for (final i in m.items) {
      final c = i.serverView;
      final repair = c.repairable;
      if (repair != null) item(repair);
      for (final rule in c.tool?.rules ?? const <ToolRule>[]) {
        blockRef(rule.blocks);
      }
    }
    for (final i in m.creativeTabs.insertions) {
      item(i.after);
    }
    return ExternalReferences(
      items: items,
      itemTags: itemTags,
      blockTags: blockTags,
      blocks: blocks,
    );
  }
}
