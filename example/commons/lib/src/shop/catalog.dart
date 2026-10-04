import 'model.dart';

/// Most items a single trade may move: a full inventory of 36 stacks of 64.
const maxTradeAmount = 36 * 64;

/// Most categories the shop menu can show (4 rows of 7 inside the border).
const maxCategories = 28;

final _categoryId = RegExp(r'^[a-z0-9_]{1,24}$');
final _itemKey = RegExp(r'^([a-z0-9_.-]+:)?[a-z0-9_./-]+$');

/// `Diamond` and `minecraft:diamond` become `minecraft:diamond`.
String normalizeItemKey(String key) {
  final lower = key.trim().toLowerCase();
  return lower.contains(':') ? lower : 'minecraft:$lower';
}

/// The key as players type it: vanilla items lose their `minecraft:`.
String shortItemKey(String key) =>
    key.startsWith('minecraft:') ? key.substring('minecraft:'.length) : key;

/// `minecraft:diamond_sword` as `Diamond Sword`, for messages.
String prettyItemName(String key) {
  final path = key.substring(key.indexOf(':') + 1);
  return [
    for (final word in path.split(RegExp(r'[_/.-]')))
      if (word.isNotEmpty) word[0].toUpperCase() + word.substring(1),
  ].join(' ');
}

/// The validated content of `shop/catalog.json`: only entries whose item
/// exists and whose numbers make sense, with normalised registry keys.
final class Catalog {
  final List<ShopCategory> categories;
  final Map<String, ShopEntry> _byKey = {};

  Catalog(this.categories) {
    for (final category in categories) {
      for (final entry in category.entries) {
        _byKey.putIfAbsent(entry.item, () => entry);
      }
    }
  }

  /// The entry for [item] (`diamond`, `minecraft:Diamond`, ...). If an item
  /// is listed in several categories, the first one counts.
  ShopEntry? find(String item) => _byKey[normalizeItemKey(item)];

  ShopCategory? category(String id) {
    final lower = id.toLowerCase();
    for (final category in categories) {
      if (category.id == lower) return category;
    }
    return null;
  }

  /// Every item name as players type it, sorted, for tab completion.
  List<String> get names =>
      ([for (final key in _byKey.keys) shortItemKey(key)]..sort());

  int get entryCount => _byKey.length;

  /// The permission nodes entries ask for.
  Set<String> get permissions => {
    for (final category in categories)
      for (final entry in category.entries)
        if (entry.permission != null) entry.permission!,
  };
}

/// A [Catalog] and what was wrong with the file it was built from.
final class CatalogReport {
  final Catalog catalog;

  /// One line per skipped category or entry, for the log and `/shopadmin
  /// reload`.
  final List<String> problems;

  const CatalogReport(this.catalog, this.problems);
}

/// Checks [raw] and keeps what is usable. Nothing here throws: a bad entry is
/// skipped and described in [CatalogReport.problems], so one typo in the file
/// never takes the shop down.
///
/// [isKnownItem] decides whether a (normalised) registry key exists on the
/// server.
CatalogReport validateCatalog(
  ShopCatalog raw, {
  required bool Function(String key) isKnownItem,
}) {
  final problems = <String>[];
  final categories = <ShopCategory>[];
  final seenIds = <String>{};

  for (final category in raw.categories) {
    final where = 'category "${category.id}"';
    if (!_categoryId.hasMatch(category.id)) {
      problems.add(
        '$where: the id must be 1-24 characters of a-z, 0-9 and _, skipped.',
      );
      continue;
    }
    if (categories.length >= maxCategories) {
      problems.add('$where: more than $maxCategories categories, skipped.');
      continue;
    }
    if (!seenIds.add(category.id)) {
      problems.add('$where: the id is used twice, skipped.');
      continue;
    }

    var icon = normalizeItemKey(category.icon);
    if (!_itemKey.hasMatch(icon) || !isKnownItem(icon)) {
      problems.add(
        '$where: unknown icon "${category.icon}", using minecraft:chest.',
      );
      icon = 'minecraft:chest';
    }

    final entries = <ShopEntry>[];
    final seenItems = <String>{};
    for (final entry in category.entries) {
      final problem = entryProblem(entry, isKnownItem);
      final key = normalizeItemKey(entry.item);
      if (problem != null) {
        problems.add('$where, item "${entry.item}": $problem, skipped.');
      } else if (!seenItems.add(key)) {
        problems.add('$where, item "${entry.item}": listed twice, skipped.');
      } else {
        entries.add(entry.copyWith(item: key));
      }
    }
    categories.add(
      ShopCategory(
        id: category.id,
        name: category.name.trim().isEmpty ? category.id : category.name,
        icon: icon,
        entries: entries,
      ),
    );
  }
  return CatalogReport(Catalog(categories), problems);
}

/// Why [e] can not be sold, or `null` if it is fine.
String? entryProblem(ShopEntry e, bool Function(String key) isKnownItem) {
  final key = normalizeItemKey(e.item);
  if (!_itemKey.hasMatch(key) || !isKnownItem(key)) return 'unknown item';
  if (e.buy < 1) return 'the buy price must be at least 1';
  if (e.sell != null && e.sell! < 0) {
    return 'the sell price can not be negative';
  }
  if (e.amount < 1 || e.amount > maxTradeAmount) {
    return 'the amount must be between 1 and $maxTradeAmount';
  }
  if (e.stack < e.amount || e.stack > maxTradeAmount) {
    return 'the stack must be between the amount and $maxTradeAmount';
  }
  final permission = e.permission;
  if (permission != null && !permission.contains(':')) {
    return 'the permission must look like plugin:node';
  }
  return null;
}
