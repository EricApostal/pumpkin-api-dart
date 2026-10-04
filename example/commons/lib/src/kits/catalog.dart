import 'model.dart';

/// Most stacks a kit may hold: the 36 slots of the main inventory.
const maxKitStacks = 36;

/// Words that are subcommands of `/kit` and so can not be kit names.
const reservedKitNames = {'preview', 'list', 'create', 'delete', 'reload'};

final _kitName = RegExp(r'^[a-z0-9_-]{1,32}$');
final _itemKey = RegExp(r'^([a-z0-9_.-]+:)?[a-z0-9_./-]+$');

/// `Bread` and `minecraft:bread` become `minecraft:bread`.
String normalizeItemKey(String key) {
  final lower = key.trim().toLowerCase();
  return lower.contains(':') ? lower : 'minecraft:$lower';
}

/// `minecraft:diamond_sword` as `Diamond Sword`, for messages.
String prettyItemName(String key) {
  final path = key.substring(key.indexOf(':') + 1);
  return [
    for (final word in path.split(RegExp(r'[_/.-]')))
      if (word.isNotEmpty) word[0].toUpperCase() + word.substring(1),
  ].join(' ');
}

/// The usable kits of `kits/kits.json` and what was wrong with the rest.
final class KitReport {
  final List<Kit> kits;

  /// One line per skipped kit or item, for the log and `/kit reload`.
  final List<String> problems;

  const KitReport(this.kits, this.problems);
}

/// Checks [raw] and keeps what is usable. Nothing throws: a broken kit is
/// skipped and described in [KitReport.problems], so one typo in the file
/// never takes the module down.
///
/// [isKnownItem] receives normalised keys (`minecraft:bread`),
/// [isKnownEnchantment] the keys as written in the file.
KitReport validateKits(
  KitCatalog raw, {
  required bool Function(String key) isKnownItem,
  required bool Function(String key) isKnownEnchantment,
}) {
  final problems = <String>[];
  final kits = <Kit>[];
  final seen = <String>{};

  for (final kit in raw.kits) {
    final where = 'kit "${kit.name}"';
    if (!_kitName.hasMatch(kit.name)) {
      problems.add(
        '$where: the name must be 1-32 characters of a-z, 0-9, _ and -, '
        'skipped.',
      );
      continue;
    }
    if (reservedKitNames.contains(kit.name)) {
      problems.add('$where: this name is a /kit subcommand, skipped.');
      continue;
    }
    if (!seen.add(kit.name)) {
      problems.add('$where: the name is used twice, skipped.');
      continue;
    }
    if (kit.cooldownSeconds < 0 || kit.price < 0) {
      problems.add('$where: cooldown and price can not be negative, skipped.');
      continue;
    }
    if (kit.items.isEmpty) {
      problems.add('$where: it has no items, skipped.');
      continue;
    }
    if (kit.items.length > maxKitStacks) {
      problems.add('$where: more than $maxKitStacks stacks, skipped.');
      continue;
    }

    final items = <KitItem>[];
    var broken = false;
    for (final item in kit.items) {
      final problem = _itemProblem(item, isKnownItem, isKnownEnchantment);
      if (problem != null) {
        problems.add('$where, item "${item.item}": $problem, skipped.');
        broken = true;
        break;
      }
      items.add(
        KitItem(
          item: normalizeItemKey(item.item),
          count: item.count,
          name: item.name,
          lore: item.lore,
          enchantments: {
            for (final e in item.enchantments.entries)
              e.key.toLowerCase().replaceFirst('minecraft:', ''): e.value,
          },
        ),
      );
    }
    // A kit with a missing item would silently give less than advertised, so
    // the whole kit is dropped rather than just the item.
    if (broken) continue;

    var icon = normalizeItemKey(kit.icon);
    if (!_itemKey.hasMatch(icon) || !isKnownItem(icon)) {
      problems.add(
        '$where: unknown icon "${kit.icon}", using minecraft:chest.',
      );
      icon = 'minecraft:chest';
    }
    kits.add(
      Kit(
        name: kit.name,
        displayName: kit.displayName,
        icon: icon,
        items: items,
        cooldownSeconds: kit.cooldownSeconds,
        oneTime: kit.oneTime,
        price: kit.price,
        restricted: kit.restricted,
      ),
    );
  }
  return KitReport(kits, problems);
}

String? _itemProblem(
  KitItem item,
  bool Function(String key) isKnownItem,
  bool Function(String key) isKnownEnchantment,
) {
  final key = normalizeItemKey(item.item);
  if (!_itemKey.hasMatch(key) || !isKnownItem(key)) return 'unknown item';
  if (item.count < 1 || item.count > 64 * 4) {
    return 'the count must be between 1 and 256';
  }
  for (final MapEntry(key: enchantment, value: level)
      in item.enchantments.entries) {
    if (!isKnownEnchantment(
      enchantment.toLowerCase().replaceFirst('minecraft:', ''),
    )) {
      return 'unknown enchantment "$enchantment"';
    }
    if (level < 1 || level > 255) {
      return 'the level of "$enchantment" must be between 1 and 255';
    }
  }
  return null;
}
