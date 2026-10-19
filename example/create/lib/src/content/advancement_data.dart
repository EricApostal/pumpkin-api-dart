// The advancement tree as data (pure): the JSON registered with the host, the
// triggers, and the inventory based criteria that the plugin has to evaluate
// itself (the host does not evaluate `minecraft:inventory_changed`).
import 'dart:convert';

import '../manifest/manifest.dart';

/// The plugin trigger that stands in for `minecraft:inventory_changed`: a criterion fires it
/// with `plugin_tag` = `<advancement>/<criterion>`.
const String inventoryCheckTrigger = 'create:inventory_check';

/// One `minecraft:inventory_changed` criterion of a Create advancement.
final class InventoryCriterion {
  final String advancementId;
  final String criterion;

  /// Item keys or `#tags` of which the player must hold at least one; empty = any change.
  final List<String> anyOf;

  const InventoryCriterion(this.advancementId, this.criterion, this.anyOf);

  /// The `plugin_tag` that identifies the criterion.
  String get tag => '$advancementId/$criterion';

  /// Whether a player holding [heldItemKeys] satisfies the criterion; [inTag] answers `#tag` entries.
  bool matches(Iterable<String> heldItemKeys, bool Function(String itemKey, String tag) inTag) {
    if (anyOf.isEmpty) return true;
    for (final key in heldItemKeys) {
      for (final want in anyOf) {
        if (want.startsWith('#')) {
          if (inTag(key, want.substring(1))) return true;
        } else if (want == key) {
          return true;
        }
      }
    }
    return false;
  }
}

/// The advancements of Create ready for registration.
final class AdvancementTree {
  /// `id` (path) to the datapack JSON with inventory criteria rewritten to [inventoryCheckTrigger].
  final Map<String, String> json = {};

  /// The inventory criteria in tree order.
  final List<InventoryCriterion> inventoryCriteria = [];

  /// Ids (paths) that can be awarded by `award` (they have a `create:<id>_builtin` criterion).
  final Set<String> awardable = {};

  /// All trigger ids to register: the `_builtin` ones and [inventoryCheckTrigger].
  final List<String> triggers = [];

  AdvancementTree._();

  /// Builds the tree from the manifest definitions (kind `create`).
  factory AdvancementTree.fromManifest([List<AdvancementDef>? defs, List<TriggerDef>? triggerDefs]) {
    final tree = AdvancementTree._();
    for (final t in triggerDefs ?? kTriggers) {
      tree.triggers.add(t.id);
    }
    tree.triggers.add(inventoryCheckTrigger);
    for (final def in defs ?? kAdvancements) {
      if (def.kind != 'create' || def.rawJson == null) continue;
      final raw = def.rawJson!;
      // Most advancements have neither a criterion the plugin rewrites nor a `_builtin`
      // trigger; their JSON is registered as it is, without decoding and encoding it again.
      if (!raw.contains('minecraft:inventory_changed') &&
          !raw.contains('_builtin')) {
        tree.json[def.id] = raw;
        continue;
      }
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final criteria = (doc['criteria'] as Map<String, dynamic>);
      var rewritten = false;
      for (final e in criteria.entries.toList()) {
        final c = e.value as Map<String, dynamic>;
        final trigger = c['trigger'] as String;
        if (trigger == 'minecraft:inventory_changed') {
          final items = <String>[];
          final conditions = c['conditions'] as Map<String, dynamic>?;
          for (final entry in (conditions?['items'] as List<dynamic>? ?? const [])) {
            final v = (entry as Map<String, dynamic>)['items'];
            if (v is String) items.add(v);
            if (v is List<dynamic>) items.addAll(v.cast<String>());
          }
          final crit = InventoryCriterion(def.id, e.key, items);
          tree.inventoryCriteria.add(crit);
          criteria[e.key] = {
            'trigger': inventoryCheckTrigger,
            'conditions': {'plugin_tag': crit.tag},
          };
          rewritten = true;
        } else if (trigger.endsWith('_builtin')) {
          tree.awardable.add(def.id);
        }
      }
      tree.json[def.id] = rewritten ? jsonEncode(doc) : raw;
    }
    return tree;
  }
}
