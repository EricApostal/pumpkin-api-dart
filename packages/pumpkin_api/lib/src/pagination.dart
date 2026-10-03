/// One page of a [Paginator].
final class Page<T> {
  /// The page number, starting at 1.
  final int number;

  /// How many pages there are (at least 1).
  final int count;

  /// The items on this page.
  final List<T> items;

  /// The index in the full list of the first item of [items].
  final int startIndex;

  /// Creates a page.
  const Page(this.number, this.count, this.items, this.startIndex);

  /// Whether there is a page before this one.
  bool get hasPrevious => number > 1;

  /// Whether there is a page after this one.
  bool get hasNext => number < count;

  /// Whether this page has no items (only possible for an empty list).
  bool get isEmpty => items.isEmpty;

  /// The 1-based position of [items] item number [i] in the full list, for
  /// numbered lists: `'${page.numberOf(i)}. ...'`.
  int numberOf(int i) => startIndex + i + 1;
}

/// Splits a list into pages. Page numbers are 1-based, like the ones players
/// type, and out of range numbers are clamped instead of failing.
///
/// ```dart
/// final pages = Paginator(homes, pageSize: 8);
/// final page = pages.page(args.integer('page'));
/// ```
final class Paginator<T> {
  /// All the items.
  final List<T> items;

  /// How many items go on a page.
  final int pageSize;

  int _current = 1;

  /// Creates a paginator over a copy of [items].
  Paginator(Iterable<T> items, {this.pageSize = 10})
    : items = List.unmodifiable(items) {
    if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize', 'Must be positive');
  }

  /// The number of pages: at least 1, even when there are no items.
  int get pageCount =>
      items.isEmpty ? 1 : (items.length + pageSize - 1) ~/ pageSize;

  /// Clamps a user supplied page [number] into `1..pageCount`.
  int clamp(int number) => number < 1 ? 1 : (number > pageCount ? pageCount : number);

  /// The page with the (clamped) 1-based [number].
  Page<T> page(int number) {
    final n = clamp(number);
    final start = items.isEmpty ? 0 : (n - 1) * pageSize;
    final end = start + pageSize > items.length ? items.length : start + pageSize;
    return Page(n, pageCount, items.sublist(start, end), start);
  }

  /// The number of the page that holds the item at [index] in the list.
  int pageOf(int index) {
    if (index < 0 || index >= items.length) {
      throw RangeError.index(index, items, 'index');
    }
    return index ~/ pageSize + 1;
  }

  /// The page number this paginator is currently on (starts at 1).
  int get currentNumber => _current;

  /// The current page.
  Page<T> get current => page(_current);

  /// Moves to the (clamped) page [number] and returns it.
  Page<T> goTo(int number) {
    _current = clamp(number);
    return page(_current);
  }

  /// Moves to the next page, stopping at the last one.
  Page<T> next() => goTo(_current + 1);

  /// Moves to the previous page, stopping at the first one.
  Page<T> previous() => goTo(_current - 1);
}

/// The text lines of a rendered page, see [renderPage].
final class RenderedPage {
  /// The header line, like `§e--- Homes (1/3) ---`.
  final String header;

  /// One line per item.
  final List<String> lines;

  /// The footer line, a bare closing rule.
  final String footer;

  /// Creates a rendered page.
  const RenderedPage(this.header, this.lines, this.footer);

  /// All lines in order: header, items, footer.
  List<String> get all => [header, ...lines, footer];
}

/// Renders [page] as legacy formatted lines: a `§e--- [title] (n/count) ---`
/// header, the items as formatted by [format] (given the item and its
/// 0-based index in the full list) and a footer rule as wide as the header.
RenderedPage renderPage<T>(
  Page<T> page, {
  required String title,
  required String Function(T item, int index) format,
  String color = '§e',
}) {
  final header = '$color--- $title (${page.number}/${page.count}) ---';
  final lines = <String>[
    for (var i = 0; i < page.items.length; i++)
      format(page.items[i], page.startIndex + i),
  ];
  // Visible width of the header without the color code.
  final footer = '$color${'-' * (header.length - color.length)}';
  return RenderedPage(header, lines, footer);
}

/// Pending "are you sure?" actions with an expiry, for flows like "type
/// `/confirm` within 10 seconds". Time is injectable, so it is easy to test.
///
/// ```dart
/// final confirmations = ConfirmationManager<void Function()>();
///
/// // in /delete:
/// confirmations.request(sender.getName(), () => deleteHome(name));
/// sender.send('&cType /confirm within 10 seconds');
///
/// // in /confirm:
/// final action = confirmations.confirm(sender.getName());
/// if (action == null) { sender.send('&cNothing to confirm'); } else { action(); }
/// ```
///
/// Use a plain `String` key such as a player's UUID or name. It keeps no host
/// handles, so it is safe to keep in a field.
final class ConfirmationManager<T> {
  final DateTime Function() _now;
  final Map<String, ({T action, DateTime expires})> _pending = {};

  /// How long a request lives when [request] gets no `ttl`.
  final Duration defaultTtl;

  /// Creates a manager. [now] defaults to `DateTime.now`.
  ConfirmationManager({
    this.defaultTtl = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Stores [action] for [key], replacing any earlier one, for [ttl] (or
  /// [defaultTtl]).
  void request(String key, T action, {Duration? ttl}) {
    _pending[key] = (action: action, expires: _now().add(ttl ?? defaultTtl));
  }

  /// Takes the pending action of [key] and returns it, or returns `null` if
  /// there is none or it has expired. Each request can be confirmed once.
  T? confirm(String key) {
    final entry = _pending.remove(key);
    if (entry == null) return null;
    return _now().isBefore(entry.expires) ? entry.action : null;
  }

  /// Whether [key] has a pending, unexpired request.
  bool hasPending(String key) {
    final entry = _pending[key];
    if (entry == null) return false;
    if (!_now().isBefore(entry.expires)) {
      _pending.remove(key);
      return false;
    }
    return true;
  }

  /// How long [key]'s request stays valid, or `null` if there is none.
  Duration? remaining(String key) =>
      hasPending(key) ? _pending[key]!.expires.difference(_now()) : null;

  /// Drops the request of [key]. Returns whether there was one.
  bool cancel(String key) => _pending.remove(key) != null;

  /// Removes all expired requests, to be called now and then (for example
  /// from a repeating task) so abandoned ones don't pile up.
  void purgeExpired() {
    final now = _now();
    _pending.removeWhere((_, e) => !now.isBefore(e.expires));
  }

  /// Number of stored requests, including expired ones not yet purged.
  int get length => _pending.length;
}
