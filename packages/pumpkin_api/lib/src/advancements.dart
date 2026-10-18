import 'dart:convert';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// Conveniences for [AdvancementProgress].
extension AdvancementProgressExt on AdvancementProgress {
  /// Whether the advancement is fully completed.
  bool get isDone => done;

  /// Whether [criterion] has been awarded.
  bool isCriterionDone(String criterion) => awardedCriteria.contains(criterion);

  /// Completed fraction of criteria, from 0.0 to 1.0.
  double get fraction {
    final total = awardedCriteria.length + remainingCriteria.length;
    return total == 0 ? (done ? 1.0 : 0.0) : awardedCriteria.length / total;
  }
}

/// Advancement helpers on players.
extension PlayerAdvancements on Player {
  /// The progress of [advancementId] (like `minecraft:story/mine_stone`), or
  /// null if the advancement does not exist.
  AdvancementProgress? advancementProgress(String advancementId) =>
      getAdvancementProgress(advancementId: advancementId);
}

/// A criterion of an [AdvancementSpec].
final class AdvancementCriterion {
  /// The trigger id, `namespace:path`: a vanilla one or one registered with
  /// [Advancements.registerTrigger].
  final String trigger;

  /// The conditions. The host only reads the `plugin_tag` string (see
  /// [AdvancementCriterion.tagged]); other conditions are kept as data and not
  /// evaluated.
  final Map<String, Object?> conditions;

  const AdvancementCriterion(this.trigger, {this.conditions = const {}});

  /// A criterion of a plugin [trigger] that only matches when
  /// `Player.triggerCriterion` is called with [tag] as the matcher.
  AdvancementCriterion.tagged(this.trigger, String tag)
    : conditions = {'plugin_tag': tag};

  Map<String, Object?> toJson() => {
    'trigger': trigger,
    if (conditions.isNotEmpty) 'conditions': conditions,
  };
}

/// An advancement to register with [Advancements.register], in the datapack
/// advancement format.
///
/// ```dart
/// Advancements.registerTrigger('my_plugin:crushed');
/// Advancements.register(const AdvancementSpec(
///   id: 'my_plugin:crush_ore',
///   title: 'Crusher',
///   description: 'Crush an ore.',
///   icon: 'minecraft:iron_ore',
///   criteria: {'crush': AdvancementCriterion('my_plugin:crushed')},
/// ));
/// await player.triggerCriterion('my_plugin:crushed');
/// ```
final class AdvancementSpec {
  /// `namespace:path`.
  final String id;
  final String title;
  final String description;

  /// Icon item id.
  final String icon;

  /// `task`, `goal` or `challenge`.
  final String frame;

  /// The parent advancement id, `null` for the root of a tab.
  final String? parent;

  /// Background texture of a root advancement, a resource location path.
  final String? background;
  final bool showToast;
  final bool announceToChat;
  final bool hidden;

  /// Criteria by name. All must be met unless [requirements] says otherwise.
  final Map<String, AdvancementCriterion> criteria;

  /// Groups of criterion names: one criterion of every group is needed. Empty
  /// means all criteria.
  final List<List<String>> requirements;

  /// Experience awarded on completion.
  final int experience;

  const AdvancementSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.criteria,
    this.frame = 'task',
    this.parent,
    this.background,
    this.showToast = true,
    this.announceToChat = true,
    this.hidden = false,
    this.requirements = const [],
    this.experience = 0,
  });

  /// The datapack JSON of the advancement.
  String toJson() => jsonEncode({
    if (parent != null) 'parent': parent,
    'display': {
      'icon': {'id': icon},
      'title': title,
      'description': description,
      'frame': frame,
      if (background != null) 'background': background,
      'show_toast': showToast,
      'announce_to_chat': announceToChat,
      'hidden': hidden,
    },
    'criteria': {for (final e in criteria.entries) e.key: e.value.toJson()},
    if (requirements.isNotEmpty) 'requirements': requirements,
    if (experience != 0) 'rewards': {'experience': experience},
  });
}

/// Runtime advancements and criterion triggers (`advancement.wit`). Plugin
/// advancements stay through datapack reloads and replace datapack ones with
/// the same id. Failures throw a [HostException].
abstract final class Advancements {
  /// Registers the criterion trigger [key] (`namespace:path`) that
  /// `Player.triggerCriterion` can fire. Can happen at any time. Triggers no
  /// plugin registered are accepted by advancements but never fire.
  static void registerTrigger(String key) => unwrapHost(
    generated.advancement.registerCriterionTrigger(key: key),
    'Registering the criterion trigger $key',
  );

  /// Adds or replaces an advancement. Online players get the updated tree.
  static void register(AdvancementSpec advancement) =>
      registerJson(advancement.id, advancement.toJson());

  /// Like [register] with the datapack advancement JSON written by hand.
  static void registerJson(String id, String json) => unwrapHost(
    generated.advancement.registerAdvancement(id: id, json: json),
    'Registering the advancement $id',
  );

  /// Removes an advancement added by a plugin. Returns false if there is none.
  static bool unregister(String id) => generated.advancement.unregisterAdvancement(id: id);
}

/// Firing criterion triggers.
extension PlayerCriterionTriggers on Player {
  /// Fires the criterion trigger [triggerKey] (see
  /// [Advancements.registerTrigger]) for this player and awards every criterion
  /// of every advancement that uses it. A criterion with a `plugin_tag`
  /// condition only matches when [matcher] equals it; one without matches any
  /// matcher. Returns how many criteria were newly awarded.
  Future<int> fireCriterion(String triggerKey, {String? matcher}) =>
      triggerCriterion(triggerKey: triggerKey, matcher: matcher);
}
