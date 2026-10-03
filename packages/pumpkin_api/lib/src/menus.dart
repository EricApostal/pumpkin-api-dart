/// Chest menus: a grid of buttons shown in a chest-style window.
///
/// What the host supports: `Gui` (a window with a screen type, a title and
/// slots) opened for a `Player` with `Player.openGui`, plus the click, drag
/// and close events. There is no host call to close a window, to read which
/// menu a click belongs to, or to move items the player's cursor holds, so:
///
/// * a menu is identified by the player: each player has at most one open
///   menu, tracked from `open` until the close event,
/// * every click and drag in a player's open menu is cancelled (vanilla item
///   movement never happens), and shift-click, double-click and number-key
///   clicks in the player's own inventory are cancelled too, since they could
///   move items into the menu,
/// * a menu can't be closed by plugin code (see [Menu.open] for the
///   workaround of opening another one), only by the player.
///
/// Call `context.installMenus()` once in `onLoad`.
///
/// ```dart
/// final menu = Menu(title: '&6Shop', rows: 3)
///   ..border(const ItemSpec('gray_stained_glass_pane', name: ' '))
///   ..button(
///     slot: MenuLayout.slot(1, 4),
///     item: const ItemSpec('diamond', name: 'Buy a diamond', lore: ['10 coins']),
///     onClick: (click) => click.player.sendMessage(
///       text: TextComponent.text(plain: 'Bought!'),
///     ),
///   );
///
/// context.registerCommand(/* ... */ ..execute((sender, server, args) {
///   menu.open(sender.asPlayer()!);
///   return 1;
/// }));
/// ```
library;

import 'dart:async';

import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import 'bindings.g.dart';
import 'events.dart';
import 'events.g.dart';
import 'item_builder.dart';
import 'logger.dart';
import 'menu_layout.dart';
import 'uuid_ext.dart';

export 'menu_layout.dart' show MenuLayout, PageLayout, menuColumns;

/// Called when a player clicks a menu button.
typedef MenuClickHandler = void Function(MenuClick click);

/// What happened in a menu click.
final class MenuClick {
  /// The player who clicked. Valid while the click handler runs (and across
  /// `await`s inside work it started).
  final Player player;

  /// The player's name.
  final String playerName;

  /// The player's UUID in canonical text form.
  final String playerId;

  /// The menu slot clicked (0 is the top left).
  final int slot;

  /// The kind of click (left, right, shift-left, number key, ...).
  final ClickType type;

  /// The menu the click happened in.
  final Menu menu;

  final _Session _session;

  MenuClick._(this.player, this.playerName, this.playerId, this.slot, this.type,
      this.menu, this._session);

  /// The row of [slot].
  int get row => MenuLayout.rowOf(slot);

  /// The column of [slot].
  int get column => MenuLayout.columnOf(slot);

  /// Whether this is a left click (plain or shift).
  bool get isLeft => type == ClickType.left || type == ClickType.shiftLeft;

  /// Whether this is a right click (plain or shift).
  bool get isRight => type == ClickType.right || type == ClickType.shiftRight;

  /// Whether shift was held.
  bool get isShift =>
      type == ClickType.shiftLeft || type == ClickType.shiftRight;

  /// The page shown to this player in a [PagedMenu], 0 for other menus.
  int get page => _session.page;

  /// Replaces what this player sees in [slot] with [item] (or empties it for
  /// `null`), without changing the menu for other viewers.
  void update(int slot, ItemSpec? item) => _session.setSlot(slot, item);

  /// Draws the whole menu again for this player, for example after changing
  /// the menu's buttons.
  void refresh() => _session.render();

  /// Opens [other] for this player in place of this menu, on the next tick
  /// (a click can't replace its own window while it is being handled).
  void open(Menu other) {
    final p = player;
    Future<void>.delayed(Duration.zero, () => other.open(p));
  }
}

/// A button: a plain item description and an optional click handler.
final class _Button {
  final ItemSpec item;
  final MenuClickHandler? onClick;
  const _Button(this.item, this.onClick);
}

/// One player's open menu.
final class _Session {
  final Menu menu;
  final String playerId;
  Inventory? inventory;
  int page = 0;
  bool opening = true;

  _Session(this.menu, this.playerId);

  void setSlot(int slot, ItemSpec? item) {
    final inv = inventory;
    if (inv == null || slot < 0 || slot >= menu.size) return;
    inv.setItem(slot: slot, item: item?.build());
  }

  void render() {
    final buttons = menu._buttonsFor(this);
    for (var s = 0; s < menu.size; s++) {
      setSlot(s, buttons[s]?.item);
    }
  }

  void dispose() {
    inventory?.dispose();
    inventory = null;
  }
}

final Map<String, _Session> _sessions = {};
bool _installed = false;

TextComponent _titleText(String text) => text.contains('&')
    ? TextComponent.fromLegacyStringWithCode(input: text, codeSymbol: 0x26)
    : TextComponent.text(plain: text);

/// A chest menu: [rows] rows of 9 slots, each holding a button or nothing.
///
/// Menus hold plain data ([ItemSpec]s), never host resources, so one `Menu`
/// can be built once and opened for any number of players. Every open
/// rebuilds the item stacks.
///
/// ```dart
/// final menu = Menu(title: 'Warps', rows: 1)
///   ..button(slot: 0, item: const ItemSpec('grass_block', name: 'Spawn'),
///       onClick: (c) => print('${c.playerName} chose spawn'));
/// menu.open(player);
/// ```
///
/// Changing buttons later (`button`, `set`, `clear`, `fill`...) updates the
/// windows that are currently open for this menu. Whether the client redraws
/// slots changed in an open window depends on the host sending inventory
/// updates; see `docs/menus.md`.
class Menu {
  /// The title. `&` followed by a colour or format code (`&6Shop`) is parsed
  /// as legacy formatting.
  final String title;

  /// Number of rows, 1 to 6.
  final int rows;

  /// Called when a player closes this menu, or when it is replaced by
  /// another menu (also when the player leaves). The player is valid inside
  /// the callback.
  void Function(Player player)? onClose;

  /// Called after the menu was opened for a player.
  void Function(Player player)? onOpen;

  final Map<int, _Button> _buttons = {};

  /// Creates an empty menu.
  Menu({required this.title, this.rows = 3, this.onClose, this.onOpen}) {
    if (rows < minMenuRows || rows > maxMenuRows) {
      throw RangeError.range(rows, minMenuRows, maxMenuRows, 'rows');
    }
  }

  /// Total number of slots.
  int get size => MenuLayout.size(rows);

  Screen get _screen => Screen.values[rows - 1];

  Map<int, _Button> _buttonsFor(_Session session) => _buttons;

  void _checkSlot(int slot) {
    if (slot < 0 || slot >= size) {
      throw RangeError.range(slot, 0, size - 1, 'slot');
    }
  }

  Iterable<_Session> get _open =>
      _sessions.values.where((s) => identical(s.menu, this)).toList();

  void _push(int slot) {
    for (final s in _open) {
      s.setSlot(slot, s.menu._buttonsFor(s)[slot]?.item);
    }
  }

  /// Puts a button in [slot], or at [row] and [column] when those are given
  /// instead. [onClick] runs when a player clicks it; without it the item is
  /// decoration. Replaces whatever was there.
  ///
  /// ```dart
  /// menu.button(row: 1, column: 4, item: const ItemSpec('apple'), onClick: (c) {});
  /// ```
  void button({
    int? slot,
    int? row,
    int? column,
    required ItemSpec item,
    MenuClickHandler? onClick,
  }) {
    final s = _resolve(slot, row, column);
    _checkSlot(s);
    _buttons[s] = _Button(item, onClick);
    _push(s);
  }

  /// Puts a decorative item (no click handler) in [slot].
  void set(int slot, ItemSpec item) => button(slot: slot, item: item);

  int _resolve(int? slot, int? row, int? column) {
    if (slot != null) return slot;
    if (row != null && column != null) return MenuLayout.slot(row, column);
    throw ArgumentError('Give either slot or both row and column');
  }

  /// Empties [slot].
  void clear(int slot) {
    _checkSlot(slot);
    _buttons.remove(slot);
    _push(slot);
  }

  /// Empties every slot.
  void clearAll() {
    final slots = _buttons.keys.toList();
    _buttons.clear();
    slots.forEach(_push);
  }

  /// The slots currently holding a button.
  Set<int> get usedSlots => _buttons.keys.toSet();

  /// Fills empty slots with [item], or every slot with [overwrite].
  void fill(ItemSpec item, {bool overwrite = false, MenuClickHandler? onClick}) =>
      _fillSlots(MenuLayout.allSlots(rows), item, overwrite, onClick);

  /// Puts [item] on the outer edge. With [overwrite] existing buttons are
  /// replaced.
  void border(ItemSpec item, {bool overwrite = true}) =>
      _fillSlots(MenuLayout.borderSlots(rows), item, overwrite, null);

  /// Fills [row] with [item].
  void fillRow(int row, ItemSpec item, {bool overwrite = true}) =>
      _fillSlots(MenuLayout.rowSlots(row), item, overwrite, null);

  /// Fills [column] with [item].
  void fillColumn(int column, ItemSpec item, {bool overwrite = true}) =>
      _fillSlots(MenuLayout.columnSlots(column, rows), item, overwrite, null);

  void _fillSlots(List<int> slots, ItemSpec item, bool overwrite,
      MenuClickHandler? onClick) {
    for (final s in slots) {
      if (s >= size) continue;
      if (!overwrite && _buttons.containsKey(s)) continue;
      button(slot: s, item: item, onClick: onClick);
    }
  }

  /// Redraws this menu for everyone who has it open.
  void refreshAll() {
    for (final s in _open) {
      s.render();
    }
  }

  /// How many players currently have this menu open.
  int get viewerCount => _open.length;

  /// Opens the menu for [player]. If the player already has a menu open it is
  /// replaced (its `onClose` runs); that is also how to "close" a menu from
  /// code, as the host has no close call: open a menu that suits as the next
  /// screen.
  ///
  /// Needs `context.installMenus()` to have been called. The [Gui] handed to
  /// the host is built from fresh item stacks on every call.
  void open(Player player) {
    if (!_installed) {
      throw StateError('Call Context.installMenus() in onLoad before opening menus.');
    }
    final id = player.getId().asString;
    final previous = _sessions[id];
    final session = _Session(this, id);
    _sessions[id] = session;

    final gui = _buildGui(session);
    session.inventory = gui.getInventory().keep();
    try {
      player.openGui(guiRef: gui);
    } catch (_) {
      _sessions.remove(id);
      session.dispose();
      if (previous != null) _sessions[id] = previous;
      rethrow;
    } finally {
      session.opening = false;
    }
    if (previous != null) {
      _finish(previous, player);
    }
    onOpen?.call(player);
  }

  Gui _buildGui(_Session session) {
    final gui = Gui.create(type: _screen, title: _titleText(title));
    gui.allowGrabItems = false;
    gui.allowPutItems = false;
    for (final entry in _buttonsFor(session).entries) {
      gui.setItem(slot: entry.key, item: entry.value.item.build());
    }
    return gui;
  }

  /// A new [Gui] showing this menu's first page, for use with
  /// `Player.openGui` when you manage the window yourself (no click handling
  /// happens for it). `open` is what you normally want.
  Gui toGui() => _buildGui(_Session(this, ''));

  /// Opens a fresh copy of the current state for [player] again. Use it if
  /// in-place updates don't reach the client.
  void reopen(Player player) => open(player);
}

void _finish(_Session session, Player? player) {
  final close = session.menu.onClose;
  session.dispose();
  if (close != null && player != null) {
    try {
      close(player);
    } catch (e, st) {
      logger.error('Menu onClose failed', error: e, stackTrace: st);
    }
  }
}

/// A menu showing a long list of entries over several pages, with previous
/// and next buttons in the bottom row. Each player has their own page.
///
/// ```dart
/// final warps = PagedMenu<String>(
///   title: 'Warps',
///   items: () => ['spawn', 'mine', 'farm', /* ... */],
///   render: (name) => ItemSpec('compass', name: name),
///   onSelect: (click, name) => print('${click.playerName} -> $name'),
/// );
/// warps.open(player);
/// ```
///
/// The bottom row is reserved for navigation (previous at column 3, a page
/// indicator at column 4, next at column 5); other buttons added with
/// `button` live in the bottom row or override entry slots.
class PagedMenu<T> extends Menu {
  /// Supplies the entries; called whenever a page is drawn, so the list can
  /// change between pages.
  final List<T> Function() items;

  /// Describes the item that represents an entry.
  final ItemSpec Function(T entry) render;

  /// Called when an entry is clicked.
  final void Function(MenuClick click, T entry)? onSelect;

  /// Item of the "previous page" button.
  final ItemSpec previousItem;

  /// Item of the "next page" button.
  final ItemSpec nextItem;

  late final PageLayout _layout = PageLayout(rows);

  /// Creates a paged menu with [rows] rows (2 to 6).
  PagedMenu({
    required super.title,
    super.rows = 6,
    required this.items,
    required this.render,
    this.onSelect,
    this.previousItem = const ItemSpec('arrow', name: '&ePrevious page'),
    this.nextItem = const ItemSpec('arrow', name: '&eNext page'),
    super.onClose,
    super.onOpen,
  }) {
    if (rows < 2) throw RangeError.range(rows, 2, maxMenuRows, 'rows');
  }

  /// Entries per page.
  int get pageSize => _layout.pageSize;

  /// Number of pages for the current entries.
  int get pageCount => _layout.pageCount(items().length);

  @override
  Map<int, _Button> _buttonsFor(_Session session) {
    final all = items();
    final layout = _layout;
    final page = session.page = layout.clampPage(session.page, all.length);
    final pages = layout.pageCount(all.length);
    final result = <int, _Button>{};
    final (start, end) = layout.range(page, all.length);
    for (var i = start; i < end; i++) {
      final entry = all[i];
      final slot = layout.contentSlots[i - start];
      result[slot] = _Button(
        render(entry),
        onSelect == null ? null : (click) => onSelect!(click, entry),
      );
    }
    if (page > 0) {
      result[layout.previousSlot] = _Button(
        previousItem,
        (c) => _go(c._session, page - 1),
      );
    }
    if (page < pages - 1) {
      result[layout.nextSlot] = _Button(
        nextItem,
        (c) => _go(c._session, page + 1),
      );
    }
    result[layout.indicatorSlot] = _Button(
      ItemSpec('paper', name: '&7Page ${page + 1}/$pages', count: (page + 1).clamp(1, 64)),
      null,
    );
    result.addAll(_buttons);
    return result;
  }

  void _go(_Session session, int page) {
    session.page = page;
    session.render();
  }

  bool _dirty = false;

  @override
  void _push(int slot) {
    if (_dirty) return;
    _dirty = true;
    scheduleMicrotask(() {
      _dirty = false;
      refreshAll();
    });
  }
}

/// Open menus and listeners.
extension MenuContextApi on Context {
  /// Starts handling menu clicks and closes. Call once in `onLoad`; without
  /// it `Menu.open` throws. Safe to call more than once.
  void installMenus() {
    if (_installed) return;
    _installed = true;

    intercept(Events.inventoryClick, (server, event) {
      final id = event.player.getId().asString;
      final session = _sessions[id];
      if (session == null || session.opening) return event;
      final menu = session.menu;
      final window = event.windowType;
      if (window != null && window != menu._screen) return event;
      final slot = event.rawSlot;
      if (slot >= 0 && slot < menu.size) {
        final button = menu._buttonsFor(session)[slot];
        final handler = button?.onClick;
        if (handler != null) {
          try {
            handler(MenuClick._(event.player, event.player.getName(), id, slot,
                event.clickType, menu, session));
          } catch (e, st) {
            logger.error('Menu click handler failed', error: e, stackTrace: st);
          }
        }
        return event.copyWith(cancelled: true);
      }
      // A click in the player's own inventory: only the kinds that could
      // move items into the menu are cancelled.
      return switch (event.clickType) {
        ClickType.shiftLeft ||
        ClickType.shiftRight ||
        ClickType.doubleClick ||
        ClickType.numberKey ||
        ClickType.unknown => event.copyWith(cancelled: true),
        _ => event,
      };
    });

    intercept(Events.inventoryDrag, (server, event) {
      final id = event.player.getId().asString;
      final session = _sessions[id];
      if (session == null || session.opening) return event;
      return event.copyWith(cancelled: true);
    });

    listen(Events.inventoryClose, (server, event) {
      final id = event.player.getId().asString;
      final session = _sessions[id];
      // A close that arrives while the next menu is being opened belongs to
      // the previous window; `Menu.open` finishes that one itself.
      if (session == null || session.opening) return;
      _sessions.remove(id);
      _finish(session, event.player);
    });

    listen(Events.playerLeave, (server, event) {
      final id = event.player.getId().asString;
      final session = _sessions.remove(id);
      if (session != null) _finish(session, event.player);
    });
  }
}

/// Opens menus from the player side.
extension PlayerMenus on Player {
  /// Opens [menu] for this player. Same as `menu.open(player)`.
  void openMenu(Menu menu) => menu.open(this);

  /// The menu this player has open, or `null`.
  Menu? get currentMenu => _sessions[getId().asString]?.menu;
}
