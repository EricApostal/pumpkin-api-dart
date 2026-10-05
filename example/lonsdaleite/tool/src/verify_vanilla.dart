/// Checks [ItemProperties] against the vanilla items of an extractor dump
/// (Pumpkin's `assets/items.json`): each vanilla tool, spear and armor piece
/// must come out of the builder with exactly the components the game gives it.
library;

import 'dart:convert';

import 'vanilla.dart';

/// The result of one verification run.
final class VerificationReport {
  /// Vanilla items the builders reproduced exactly.
  final List<String> matched = [];

  /// Human readable differences.
  final List<String> mismatches = [];

  /// Facts the builders rely on that did not hold.
  final List<String> failedChecks = [];

  bool get ok => mismatches.isEmpty && failedChecks.isEmpty;
}

/// Compares the model with every vanilla item it covers.
VerificationReport verifyAgainstVanilla(Json itemsDump) {
  final report = VerificationReport();
  Json? components(String name) {
    final entry = itemsDump[name] as Json?;
    return entry == null ? null : entry['components'] as Json;
  }

  void compare(String name, ItemProperties built, {Set<String> ignore = const {}}) {
    final actual = components(name);
    if (actual == null) return;
    final expected = _normalize({...built.components}..removeWhere((k, _) => ignore.contains(k)));
    final real = _normalize({...actual}..removeWhere((k, _) => ignore.contains(k)));
    final keys = {...expected.keys, ...real.keys}.toList()..sort();
    final diffs = [
      for (final k in keys)
        if (jsonEncode(expected[k]) != jsonEncode(real[k]))
          '$k: model ${jsonEncode(expected[k])} vs vanilla ${jsonEncode(real[k])}',
    ];
    if (diffs.isEmpty) {
      report.matched.add(name);
    } else {
      report.mismatches.add('$name\n  ${diffs.join('\n  ')}');
    }
  }

  // Netherite gear is fire resistant through Items.java, not through a builder.
  // Wooden gear is furnace fuel, also from Items.java.
  Set<String> ignoreFor(String material) => {
    if (material == 'netherite') 'minecraft:damage_resistant',
    if (material == 'wooden') 'minecraft:cooking_fuel',
  };

  // Items with no builder at all.
  compare('flint', ItemProperties('minecraft:flint'));
  compare('stone', ItemProperties('minecraft:stone')..useBlockDescriptionPrefix());

  final constantParams = <String, Set<double>>{};
  for (final entry in vanillaToolMaterials.entries) {
    final material = entry.value;
    for (final type in ['pickaxe', 'axe', 'shovel', 'hoe', 'sword']) {
      final name = '${entry.key}_$type';
      final actual = components(name);
      if (actual == null) continue;
      final modifiers = (actual['minecraft:attribute_modifiers']! as List<Object?>).cast<Json>();
      final damage = (modifiers[0]['amount']! as num).toDouble() - material.attackDamageBonus;
      final speed = (modifiers[1]['amount']! as num).toDouble();
      constantParams.putIfAbsent(type, () => {}).add(damage);
      final p = ItemProperties('minecraft:$name');
      switch (type) {
        case 'pickaxe':
          p.pickaxe(material, damage, speed);
        case 'axe':
          p.axe(material, damage, speed);
        case 'shovel':
          p.shovel(material, damage, speed);
        case 'hoe':
          p.hoe(material, damage, speed);
        case 'sword':
          p.sword(material, damage, speed);
      }
      compare(name, p, ignore: ignoreFor(entry.key));
    }

    final spearName = '${entry.key}_spear';
    final spear = components(spearName);
    if (spear != null) {
      final kinetic = spear['minecraft:kinetic_weapon']! as Json;
      final dismount = kinetic['dismount_conditions']! as Json;
      final knockback = kinetic['knockback_conditions']! as Json;
      final damage = kinetic['damage_conditions']! as Json;
      double seconds(Object? tickValue) => (tickValue! as num) / 20;
      final animation = spear['minecraft:attack_animation']! as Json;
      final p = ItemProperties('minecraft:$spearName')
        ..spear(
          material,
          swingSeconds: seconds(animation['duration']),
          damageMultiplier: (kinetic['damage_multiplier']! as num).toDouble(),
          delaySeconds: seconds(kinetic['delay_ticks']),
          dismountSeconds: seconds(dismount['max_duration_ticks']),
          dismountSpeed: (dismount['min_speed']! as num).toDouble(),
          knockbackSeconds: seconds(knockback['max_duration_ticks']),
          knockbackSpeed: (knockback['min_speed']! as num).toDouble(),
          damageSeconds: seconds(damage['max_duration_ticks']),
          damageRelativeSpeed: (damage['min_relative_speed']! as num).toDouble(),
        );
      compare(spearName, p, ignore: ignoreFor(entry.key));
    }
  }

  // The damage argument is the same for every tier of these tools, which is
  // what makes "attribute = argument + material bonus" the right model.
  for (final type in ['pickaxe', 'shovel', 'sword']) {
    final values = constantParams[type];
    if (values != null && values.length > 1) {
      report.failedChecks.add('$type damage argument differs between tiers: $values');
    }
  }

  for (final entry in vanillaArmorMaterials.entries) {
    for (final type in ArmorType.values) {
      final name = '${entry.key}_${type.name}';
      final p = ItemProperties('minecraft:$name')..humanoidArmor(entry.value, type);
      compare(name, p, ignore: ignoreFor(entry.key));
    }
  }
  return report;
}

/// Round-trips through JSON so ints and doubles compare by their printed form
/// regardless of key order.
Json _normalize(Json value) => jsonDecode(jsonEncode(_sorted(value))) as Json;

Object? _sorted(Object? value) => switch (value) {
  final Map<String, Object?> m => {
    for (final k in m.keys.toList()..sort()) k: _sorted(m[k]),
  },
  final List<Object?> l => [for (final e in l) _sorted(e)],
  _ => value,
};
