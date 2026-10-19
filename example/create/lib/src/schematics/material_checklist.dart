// `MaterialChecklist` (pure): which items a schematic needs, which the cannon gathered, and the
// lines of the printed book / clipboard.
import 'item_requirement.dart';

/// `MaterialChecklist`.
final class MaterialChecklist {
  static const int maxEntriesPerPage = 5;
  static const int maxEntriesPerClipboardPage = 7;

  final Map<String, int> gathered = {};
  final Map<String, int> required = {};
  final Map<String, int> damageRequired = {};
  bool blocksNotLoaded = false;

  /// The max damage per item for damage requirements (`new ItemStack(item).getMaxDamage()`);
  /// the host fills it, 1 when unknown.
  int Function(String item) maxDamageOf = (_) => 1;

  void warnBlockNotLoaded() => blocksNotLoaded = true;

  void clear() {
    required.clear();
    damageRequired.clear();
    gathered.clear();
    blocksNotLoaded = false;
  }

  /// `require`.
  void require(ItemRequirement requirement) {
    if (requirement.isEmpty || requirement.isInvalid) return;
    for (final stack in requirement.requiredItems) {
      if (stack.item == 'minecraft:air') continue;
      final map = stack.usage == ItemUseType.damage ? damageRequired : required;
      map[stack.item] = (map[stack.item] ?? 0) + stack.count;
    }
  }

  /// `collect`: counts [count] items of [item] if the schematic needs it.
  void collect(String item, int count) {
    if (required.containsKey(item) || damageRequired.containsKey(item)) {
      gathered[item] = (gathered[item] ?? 0) + count;
    }
  }

  /// `getRequiredAmount`.
  int getRequiredAmount(String item) {
    var amount = required[item] ?? 0;
    final damage = damageRequired[item];
    if (damage != null) amount += (damage / maxDamageOf(item)).ceil();
    return amount;
  }

  /// All item keys, sorted by their display name (here: the key's path).
  List<String> sortedItems() {
    final keys = {...required.keys, ...damageRequired.keys}.toList();
    keys.sort((a, b) => displayName(a).toLowerCase().compareTo(displayName(b).toLowerCase()));
    return keys;
  }

  /// The English-ish name of an item key: `minecraft:oak_log` -> `Oak Log`.
  static String displayName(String key) {
    final path = key.contains(':') ? key.substring(key.indexOf(':') + 1) : key;
    return path.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  /// The entries still missing (item, amount missing), and the completed ones, in display order.
  ({List<(String, int)> missing, List<(String, int)> completed}) entries() {
    final missing = <(String, int)>[];
    final completed = <(String, int)>[];
    for (final item in sortedItems()) {
      var amount = getRequiredAmount(item);
      if (gathered.containsKey(item)) amount -= gathered[item]!;
      if (amount <= 0) {
        completed.add((item, getRequiredAmount(item)));
      } else {
        missing.add((item, amount));
      }
    }
    return (missing: missing, completed: completed);
  }

  /// `entry(...)`: the styled parts of one entry: the item name (with a check mark in a finished
  /// book entry), the amount, and the stacks and remainder.
  static List<StyledPart> entryParts(String item, int amount, {required bool unfinished, required bool forBook}) {
    final stacks = amount ~/ 64;
    final remainder = amount % 64;
    final tick = (!unfinished && forBook) ? ' \u2714' : '';
    final nameColor = (!unfinished || forBook) ? (unfinished ? BookColor.blue : BookColor.darkGreen) : null;
    return [
      StyledPart('${displayName(item)}$tick', nameColor),
      StyledPart('\n x$amount', BookColor.black),
      StyledPart(' | $stacks\u25A4 +$remainder${forBook ? '\n' : ''}', BookColor.gray),
    ];
  }

  /// The plain text of an entry.
  static String entryText(String item, int amount, {required bool unfinished, required bool forBook}) =>
      entryParts(item, amount, unfinished: unfinished, forBook: forBook).map((p) => p.text).join();

  /// The pages of the written book: each page is a list of entries (styled parts), and the page
  /// breaks carry a `>>>` marker.
  List<BookPage> bookPages() {
    final pages = <BookPage>[];
    var current = <List<StyledPart>>[];
    if (blocksNotLoaded) {
      pages.add(BookPage([
        [const StyledPart('\nBlocks not loaded', BookColor.red)],
      ]));
    }
    final e = entries();
    var written = 0;
    for (final (item, amount) in e.missing) {
      if (written == maxEntriesPerPage) {
        written = 0;
        current.add([const StyledPart('\n >>>', BookColor.blue)]);
        pages.add(BookPage(current));
        current = [];
      }
      written++;
      current.add(entryParts(item, amount, unfinished: true, forBook: true));
    }
    for (final (item, amount) in e.completed) {
      if (written == maxEntriesPerPage) {
        written = 0;
        current.add([const StyledPart('\n >>>', BookColor.darkGreen)]);
        pages.add(BookPage(current));
        current = [];
      }
      written++;
      current.add(entryParts(item, amount, unfinished: false, forBook: true));
    }
    pages.add(BookPage(current));
    return pages;
  }

  /// The pages of the written clipboard.
  List<List<ClipboardLine>> clipboardPages() {
    final pages = <List<ClipboardLine>>[];
    var current = <ClipboardLine>[];
    if (blocksNotLoaded) {
      current.add(const ClipboardLine(false, [StyledPart('Blocks not loaded', BookColor.red)]));
    }
    final e = entries();
    var written = 0;
    for (final (item, amount) in e.missing) {
      if (written == maxEntriesPerClipboardPage) {
        written = 0;
        current.add(const ClipboardLine(false, [StyledPart('>>>', BookColor.darkGray)]));
        pages.add(current);
        current = [];
      }
      written++;
      current.add(ClipboardLine(false, entryParts(item, amount, unfinished: true, forBook: false), icon: item, iconAmount: amount));
    }
    for (final (item, amount) in e.completed) {
      if (written == maxEntriesPerClipboardPage) {
        written = 0;
        current.add(const ClipboardLine(true, [StyledPart('>>>', BookColor.darkGreen)]));
        pages.add(current);
        current = [];
      }
      written++;
      current.add(ClipboardLine(true, entryParts(item, amount, unfinished: false, forBook: false), icon: item, iconAmount: 0));
    }
    pages.add(current);
    return pages;
  }
}

enum BookColor {
  red('red'),
  blue('blue'),
  darkGreen('dark_green'),
  darkGray('dark_gray'),
  black('black'),
  gray('gray');

  const BookColor(this.id);

  final String id;
}

/// A run of text with a color (null: the color of the parent).
final class StyledPart {
  final String text;
  final BookColor? color;

  const StyledPart(this.text, [this.color]);
}

final class BookPage {
  /// Entries; each entry is a list of styled parts.
  final List<List<StyledPart>> entries;

  const BookPage(this.entries);
}

final class ClipboardLine {
  final bool checked;
  final List<StyledPart> parts;
  final String? icon;
  final int iconAmount;

  const ClipboardLine(this.checked, this.parts, {this.icon, this.iconAmount = 0});

  String get text => parts.map((p) => p.text).join();
}
