// The server side of the filter screens (`FilterMenu`, `AttributeFilterMenu`,
// `PackageFilterMenu`). The screens are opened as plugin menus without server tracked slots
// (`Menus.getOpenMenu` only reports plugin menus), so the plugin keeps the filter state itself:
// the ghost inventory lives in the session, `create:configure_filter` / `create:clear_container`
// change it, and the clicks on the client's ghost slots arrive as `menu-click-event` and are
// applied with the same rules (`filter_menu_clicks.dart`). Every change is written back at once,
// so the server state and the client's copy stay in step.
//
// The edited stack is the filter item in the player's hand (using a filter item opens its
// screen, `FilterItem.use`).
import 'dart:async';
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart' hide ItemAttribute;
// The `menus` interface (options, rules, cursor) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../core/nbt.dart';
import '../host/runtime.dart';
import '../model/package.dart';
import '../model/stack.dart';
import 'filter_item_stack.dart';
import 'filter_menu_clicks.dart';
import 'item_attribute.dart';

export 'filter_menu_clicks.dart' show FilterMenuKind;

/// Where the edited filter stack lives.
abstract interface class FilterTarget {
  Future<void> write(LStack filter);

  /// Releases host handles held beyond the callback that created the session.
  void dispose() {}
}

/// The filter item in the player's selected hotbar slot (`HeldItemGhostItemMenu`). The slot is
/// fixed when the screen opens, so switching items does not write the filter into another stack.
final class HeldFilterTarget implements FilterTarget {
  final Player player;
  final int slot;

  /// A session stored until the screen closes must [Player.keep] the player, because the event
  /// that opened it releases its handle when the callback returns.
  final bool ownsPlayer;

  const HeldFilterTarget(this.player, this.slot, {this.ownsPlayer = false});

  @override
  void dispose() {
    if (ownsPlayer) player.dispose();
  }

  @override
  Future<void> write(LStack filter) async {
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      final current = inventory.getItem(slot: slot);
      if (current == null) return;
      // The player changed the stack while the screen was open: do not overwrite it.
      if (await current.getRegistryKey() != filter.key) return;
      final host = await Lg.i.write(filter);
      await inventory.setItem(slot: slot, item: host);
    } finally {
      inventory.dispose();
    }
  }
}

/// One open filter screen: its kind, the target and the editable state.
final class FilterMenuSession {
  final FilterMenuKind kind;
  final FilterTarget target;

  /// The container id of the open screen, `-1` until it was opened.
  int containerId = -1;

  /// The filter stack the session started from (other components are preserved).
  final LStack current;

  /// `GhostItemMenu.ghostInventory`: 18 slots for a list filter, 2 for an attribute filter
  /// (slot [attributeDisplaySlot] only displays the selected attributes) and none for a package
  /// filter.
  late final FilterGhostMenu ghost = FilterGhostMenu(
    kind,
    slots: List<LStack>.filled(ghostSlotCount(kind), LStack.empty, growable: false),
  );

  List<LStack> get ghostItems => ghost.slots;

  bool blacklist = false;
  bool respectNbt = false;
  AttributeFilterWhitelistMode whitelistMode =
      AttributeFilterWhitelistMode.whitelistDisj;
  final List<ItemAttributeEntry> attributes = [];
  String address = '';

  FilterMenuSession._(this.kind, this.target, this.current);

  /// `FilterMenu` / `AttributeFilterMenu` / `PackageFilterMenu.initAndReadInventory`.
  factory FilterMenuSession.fromStack(LStack filter, FilterTarget target) {
    final kind = FilterMenuKind.of(filter.key);
    final session = FilterMenuSession._(
      kind ?? FilterMenuKind.list,
      target,
      filter,
    );
    switch (kind) {
      case FilterMenuKind.list:
        final blacklistBytes = filter.compBytes(FilterComponents.blacklist);
        final respectBytes = filter.compBytes(FilterComponents.respectNbt);
        session.blacklist =
            blacklistBytes != null &&
            blacklistBytes.isNotEmpty &&
            blacklistBytes.first != 0;
        session.respectNbt =
            respectBytes != null &&
            respectBytes.isNotEmpty &&
            respectBytes.first != 0;
        final slots = readFilterItems(filter);
        for (
          var i = 0;
          i < session.ghostItems.length && i < slots.length;
          i++
        ) {
          session.ghostItems[i] = slots[i];
        }
      case FilterMenuKind.attribute:
        final parsed = FilterItemStack.of(filter, wire: Lg.i.wire);
        if (parsed is AttributeFilterItemStack) {
          session.whitelistMode = parsed.whitelistMode;
          session.attributes.addAll(parsed.attributeTests);
        }
      case FilterMenuKind.package:
        session.address = PackageItem.getAddress(filter);
      case null:
        break;
    }
    return session;
  }

  /// The stacks in the list filter's 18 ghost slots (`create:filter_items`).
  static List<LStack> readFilterItems(LStack filter) {
    final slots = List<LStack>.filled(18, LStack.empty, growable: false);
    final bytes = filter.compBytes(FilterComponents.filterItems);
    if (bytes == null) return slots;
    try {
      final decoded = PacketBuffer.decode(bytes, Lg.i.wire.readContents);
      for (var i = 0; i < slots.length && i < decoded.length; i++) {
        slots[i] = decoded[i];
      }
    } on Object {
      // an unreadable component reads as an empty filter
    }
    return slots;
  }

  /// `FilterScreenPacket.handle`: applies one option. Returns whether the state changed.
  bool apply(int option, NbtValue? data) {
    final tag = data != null && data.kind == NbtKind.compound
        ? data.asCompound
        : const <String, NbtValue>{};

    switch (kind) {
      case FilterMenuKind.list:
        switch (option) {
          case 0: // WHITELIST
            blacklist = false;
            return true;
          case 2: // BLACKLIST
            blacklist = true;
            return true;
          case 3: // RESPECT_DATA
            respectNbt = true;
            return true;
          case 4: // IGNORE_DATA
            respectNbt = false;
            return true;
          case 5: // UPDATE_FILTER_ITEM
            final slot = _int(tag['Slot']) ?? 0;
            if (slot < 0 || slot >= ghostItems.length) return false;
            ghostItems[slot] = _itemStack(tag['Item']);
            return true;
        }
      case FilterMenuKind.attribute:
        switch (option) {
          case 0: // WHITELIST
            whitelistMode = AttributeFilterWhitelistMode.whitelistDisj;
            return true;
          case 1: // WHITELIST2
            whitelistMode = AttributeFilterWhitelistMode.whitelistConj;
            return true;
          case 2: // BLACKLIST
            whitelistMode = AttributeFilterWhitelistMode.blacklist;
            return true;
          case 6: // ADD_TAG
          case 7: // ADD_INVERTED_TAG
            final attribute = _attribute(tag['attribute']);
            if (attribute == null) return false;
            attributes.add(ItemAttributeEntry(attribute, option == 7));
            return true;
        }
      case FilterMenuKind.package:
        if (option == 8) {
          // UPDATE_ADDRESS
          final value = tag['Address'];
          address = value != null && value.kind == NbtKind.string
              ? value.value as String
              : '';
          return true;
        }
    }
    return false;
  }

  /// `GhostItemMenu.clicked` / `quickMoveStack` for one click on the client's menu. [menuSlot]
  /// is the client's slot index: the player inventory slots 0 to 35, then the ghost slots.
  /// [source] is the stack of the clicked player inventory slot (only read for a shift-click from
  /// it). Returns whether the ghost inventory changed.
  bool applyClick({
    required int menuSlot,
    required int button,
    required GhostClickMode mode,
    required LStack carried,
    LStack source = LStack.empty,
    bool creative = false,
  }) => ghost.apply(
    ghost.click(
      menuSlot: menuSlot,
      button: button,
      mode: mode,
      carried: carried,
      source: source,
      creative: creative,
    ),
  );

  /// `GhostItemSubmitPacket.handle` (a JEI drag onto a ghost slot): writes the slot directly.
  /// Returns false for a slot the menu does not have.
  bool setGhost(int slot, LStack stack) {
    if (slot < 0 || slot >= ghostItems.length) return false;
    // The display slot of the attribute filter lists the selection; JEI never targets it.
    if (kind == FilterMenuKind.attribute && slot == attributeDisplaySlot) {
      return false;
    }
    ghostItems[slot] = stack;
    return true;
  }

  /// `IClearableMenu.clearContents` of the three menus.
  void clear() {
    switch (kind) {
      case FilterMenuKind.list:
        for (var i = 0; i < ghostItems.length; i++) {
          ghostItems[i] = LStack.empty;
        }
      case FilterMenuKind.attribute:
        attributes.clear();
      case FilterMenuKind.package:
        address = '';
    }
  }

  /// Writes the state back to the edited filter item.
  Future<void> save() async {
    var filter = current;
    switch (kind) {
      case FilterMenuKind.list:
        final hasItems = ghostItems.any((s) => s.isNotEmpty);
        if (hasItems) {
          final bytes = PacketBuffer.encode(
            (w) => Lg.i.wire.writeContents(w, ghostItems),
          );
          filter = filter.withComp(FilterComponents.filterItems, bytes);
        } else {
          filter = filter.withComp(FilterComponents.filterItems, null);
        }
        filter = filter.withComp(FilterComponents.respectNbt, [
          respectNbt ? 1 : 0,
        ]);
        filter = filter.withComp(FilterComponents.blacklist, [
          blacklist ? 1 : 0,
        ]);
      case FilterMenuKind.attribute:
        filter = filter.withComp(
          FilterComponents.whitelistMode,
          _varInt(whitelistMode.index),
        );
        filter = _withAttributes(filter);
      case FilterMenuKind.package:
        // `PackageFilterMenu.saveData` also calls `super.saveData`, whose ghost inventory has no
        // editable slot, so it always removes the item list.
        filter = filter.withComp(FilterComponents.filterItems, null);
        final bytes = PacketBuffer.encode((w) => w.writeString(address));
        filter = filter.withComp(PackageComponents.address, bytes);
    }
    await target.write(filter);
  }

  /// Releases the target's host handles (a kept player).
  void dispose() => target.dispose();

  /// The attribute entries in the private `minecraft:custom_data` key, because the standard
  /// `create:attribute_filter_matched_attributes` component is a registry dispatch whose ids the
  /// host does not expose for encoding. `FilterItemStack` reads the same key.
  LStack _withAttributes(LStack filter) {
    var root = <String, NbtValue>{};
    final customData = filter.compBytes('minecraft:custom_data');
    if (customData != null) {
      try {
        root = Map<String, NbtValue>.of(
          NetworkNbt.decode(customData)?.asCompound ?? const {},
        );
      } on Object {
        root = {};
      }
    }
    if (attributes.isEmpty) {
      root.remove(FilterComponents.privateAttributes);
    } else {
      root[FilterComponents.privateAttributes] = NbtValue.string(
        jsonEncode([for (final entry in attributes) entry.toMap()]),
      );
    }
    if (root.isEmpty) return filter.withComp('minecraft:custom_data', null);
    return filter.withComp(
      'minecraft:custom_data',
      NetworkNbt.encode(NbtValue.compound(root)),
    );
  }

  static int? _int(NbtValue? value) {
    if (value == null) return null;
    final v = value.value;
    return v is int ? v : null;
  }

  /// An `ItemStack.OPTIONAL_CODEC` NBT compound (`{id, count, components}`). The ghost items are
  /// plain in practice; components are not read back into the [LStack].
  static LStack _itemStack(NbtValue? value) {
    if (value == null || value.kind != NbtKind.compound) return LStack.empty;
    final map = value.asCompound;
    final id = map['id'];
    if (id == null || id.kind != NbtKind.string) return LStack.empty;
    final count = _int(map['count']) ?? 1;
    if (count <= 0) return LStack.empty;
    return LStack(
      (id.value as String),
      count,
      maxStack: PackageStyles.styleOf(id.value as String) != null ? 1 : 64,
    );
  }

  /// `ItemAttribute.loadStatic` (`{attribute: {type, value}}`).
  static ItemAttribute? _attribute(NbtValue? value) {
    if (value == null || value.kind != NbtKind.compound) return null;
    final map = value.asCompound;
    final type = map['type'];
    if (type == null || type.kind != NbtKind.string) return null;
    final raw = map['value'];
    final converted = switch (raw?.kind) {
      null => null,
      NbtKind.byte ||
      NbtKind.short ||
      NbtKind.int ||
      NbtKind.long => raw!.value as int,
      NbtKind.float || NbtKind.double => (raw!.value as double).round(),
      NbtKind.string => raw!.value as String,
      _ => null,
    };
    return ItemAttributeRegistry.instance.attributeFromMap({
      'type': type.value as String,
      'value': converted,
    });
  }
}

/// The open filter sessions, by player uuid.
abstract final class FilterMenuSessions {
  static final Map<String, FilterMenuSession> _byPlayer = {};

  static FilterMenuSession? get(Player player) =>
      _byPlayer[player.getId().asString];

  static void put(Player player, FilterMenuSession session) =>
      _byPlayer[player.getId().asString] = session;

  /// Opens the Create screen of the filter item [filter] and starts a session for [target].
  static Future<void> open(
    Player player,
    LStack filter,
    FilterTarget target,
  ) async {
    final kind = FilterMenuKind.of(filter.key);
    if (kind == null) return;
    // The session outlives this callback, so a held-item target must keep the player handle.
    final heldTarget = target is HeldFilterTarget && !target.ownsPlayer
        ? HeldFilterTarget(target.player.keep(), target.slot, ownsPlayer: true)
        : target;
    final session = FilterMenuSession.fromStack(filter, heldTarget);
    final extra = Lg.i.wire.toData(filter).encode();
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: kind.menuType,
      title: TextComponent.translate(
        key: 'item.${kind.menuType.replaceFirst(':', '.')}',
        with_: const [],
      ),
      extraData: extra,
      slotCount: filterMenuSlotCount(kind),
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first (`AbstractFilterMenu.addSlots`), so
        // the server tracks a mirror of it instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules(kind),
      ),
    );
    if (result is! OkResult<int, String>) {
      // A Bedrock player, an unknown menu type, bad rules or a closed registration.
      Lg.i.log.warn(
        'Could not open ${kind.menuType}: ${(result as ErrorResult<int, String>).value}',
      );
      heldTarget.dispose();
      return;
    }
    final containerId = result.value;
    session.containerId = containerId;
    // A session that was still open is replaced (its changes were already written by every
    // configure packet).
    _byPlayer.remove(player.getId().asString)?.dispose();
    put(player, session);
    await _fill(player, session);
  }

  /// The click rules of the screen: the ghost slots, and the player inventory mirror as normal
  /// slots. Shift-clicks are handled by [handleClick].
  static MenuClickRules _rules(FilterMenuKind kind) => MenuClickRules(
    slotRules: [
      for (var i = 0; i < ghostSlotCount(kind); i++)
        MenuSlotRule(
          slot: ghostMenuPlayerSlots + i,
          kind: kind == FilterMenuKind.attribute && i == attributeDisplaySlot
              ? const MenuSlotKindLocked()
              : const MenuSlotKindGhost(),
          maxStackSize: 1,
        ),
    ],
    quickMoveTargets: const [],
  );

  /// Sends the player inventory mirror and the ghost slots to the client.
  static Future<void> _fill(Player player, FilterMenuSession session) async {
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      for (var menuSlot = 0; menuSlot < ghostMenuPlayerSlots; menuSlot++) {
        final index = inventoryIndexAt(menuSlot);
        if (index == null) continue;
        await _setSlotHostAsync(player, menuSlot, inventory.getItem(slot: index));
      }
    } finally {
      inventory.dispose();
    }
    for (var i = 0; i < session.ghostItems.length; i++) {
      await _setSlotAsync(player, ghostMenuPlayerSlots + i, session.ghostItems[i]);
    }
    if (session.kind == FilterMenuKind.attribute) {
      // `AttributeFilterMenu.init`: the display slot holds a name tag that lists the selection.
      try {
        final tag = ItemStack.create(registryKey: 'minecraft:name_tag', count: 1);
        await tag.setCustomName(
          name: TextComponent.translate(
            key: 'create.gui.attribute_filter.selected_attributes',
            with_: const [],
          ),
        );
        player.setPluginMenuSlot(
          ghostMenuPlayerSlots + attributeDisplaySlot,
          tag,
        );
      } on Object {
        // the menu closed meanwhile
      }
    }
    try {
      raw.menus.setMenuClickRules(player: player, rules: _rules(session.kind));
    } on Object {
      // the menu closed meanwhile
    }
  }

  /// Puts the host stack [stack] into the open menu's [menuSlot] (a copy is sent).
  static Future<void> _setSlotHostAsync(
    Player player,
    int menuSlot,
    ItemStack? stack,
  ) async {
    try {
      if (stack == null || await stack.getCount() == 0) {
        player.clearPluginMenuSlot(menuSlot);
      } else {
        player.setPluginMenuSlot(menuSlot, stack);
      }
    } on Object {
      // the menu closed meanwhile
    }
  }

  static Future<void> _setSlotAsync(
    Player player,
    int menuSlot,
    LStack? stack,
  ) async {
    final host = stack == null || stack.isEmpty ? null : await Lg.i.write(stack);
    try {
      if (host == null) {
        player.clearPluginMenuSlot(menuSlot);
      } else {
        player.setPluginMenuSlot(menuSlot, host);
      }
    } on Object {
      // the menu closed meanwhile
    }
  }

  /// Saves and forgets the session of [player] (menu closed or player left).
  static Future<void> close(Player player, {int? containerId}) async {
    final id = player.getId().asString;
    final session = _byPlayer[id];
    if (session == null) return;
    // A different screen closed (for example the one the new menu replaced).
    if (containerId != null &&
        session.containerId != -1 &&
        session.containerId != containerId) {
      return;
    }
    _byPlayer.remove(id);
    try {
      await session.save();
    } finally {
      session.dispose();
    }
  }

  static void forget(Player player) =>
      _byPlayer.remove(player.getId().asString)?.dispose();

  /// `create:configure_filter`.
  static Future<void> configure(
    Player player,
    int option,
    NbtValue? data,
  ) async {
    final session = await resolve(player);
    if (session == null) return;
    if (!session.apply(option, data)) return;
    await session.save();
  }

  /// `create:clear_container`.
  static Future<void> clear(Player player) async {
    final session = await resolve(player);
    if (session == null) return;
    session.clear();
    await session.save();
  }

  /// `Events.menuClick` of a filter screen. The host applies the vanilla clicks to the player
  /// inventory mirror and the ghost slots; the shift-clicks, number keys and creative clones on
  /// the ghost slots follow `GhostItemMenu` and are applied here. Returns whether the click was
  /// handled (the host must not apply it).
  static Future<bool> handleClick(Player player, MenuClickEventData e) async {
    final session = get(player);
    if (session == null || e.containerId != session.containerId) return false;
    if (!await _isStillValid(player, session)) {
      // `HeldItemGhostItemMenu.stillValid`: the item left the selected slot (or was replaced),
      // the screen no longer edits it.
      unawaited(close(player, containerId: session.containerId));
      return true;
    }

    final ghost = e.slot >= ghostMenuPlayerSlots &&
        e.slot < filterMenuSlotCount(session.kind);
    if (!ghost) {
      if (e.mode != MenuClickMode.quickMove) return false;
      // `GhostItemMenu.quickMoveStack(index < 36)`: a copy of one item goes into the ghost
      // inventory, the player's stack stays.
      final source = await _playerStack(player, e.slot);
      if (source.isEmpty) return true;
      if (session.applyClick(
        menuSlot: e.slot,
        button: e.button,
        mode: GhostClickMode.quickMove,
        carried: LStack.empty,
        source: source,
      )) {
        await session.save();
        await _sendGhosts(player, session);
      }
      return true;
    }

    final index = e.slot - ghostMenuPlayerSlots;
    switch (e.mode) {
      case MenuClickMode.quickMove:
        // `quickMoveStack(index >= 36)`: one item leaves the filter.
        final current = session.ghostItems[index];
        if (current.isEmpty) return true;
        session.ghostItems[index] = current.count > 1
            ? current.withCount(current.count - 1)
            : LStack.empty;
        await session.save();
        await _sendGhosts(player, session);
        return true;
      case MenuClickMode.swap:
        // A number key puts one item of the hotbar stack into the filter slot.
        final hotbar = await _hotbarStack(player, e.button);
        if (hotbar.isEmpty) return true;
        session.setGhost(index, hotbar.withCount(1));
        await session.save();
        await _sendGhosts(player, session);
        return true;
      case MenuClickMode.clone:
        // A creative middle click puts the filter entry on the cursor.
        final current = session.ghostItems[index];
        if (!player.isCreative || current.isEmpty) return true;
        try {
          raw.menus.setMenuCursor(
            player: player,
            stack: await Lg.i.write(current.withCount(current.maxStack)),
          );
        } on Object {
          // the menu closed
        }
        return true;
      default:
        // `GhostItemMenu.clicked` writes one item of the cursor into the slot; the host's ghost
        // slot rule does exactly that.
        return false;
    }
  }

  /// `Events.menuSlotChanged`: the player inventory mirror is written back to the real
  /// inventory, the ghost slots the host changed (a cursor click) are mirrored into the session.
  static Future<void> handleSlotChanged(
    Player player,
    MenuSlotChangedEventData e,
  ) async {
    final session = get(player);
    if (session == null || e.containerId != session.containerId) return;
    var ghostChanged = false;
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      for (final change in e.changes) {
        if (change.slot >= ghostMenuPlayerSlots) {
          final index = change.slot - ghostMenuPlayerSlots;
          if (index < 0 || index >= session.ghostItems.length) continue;
          if (session.kind == FilterMenuKind.attribute &&
              index == attributeDisplaySlot) {
            continue;
          }
          session.ghostItems[index] = await Lg.i.read(change.stack);
          ghostChanged = true;
          continue;
        }
        final index = inventoryIndexAt(change.slot);
        if (index == null) continue;
        // The mirror can fall behind the real inventory (an item picked up while the screen is
        // open). When it did, the menu's value is stale: keep the real stack and correct the
        // client instead of overwriting it.
        final previous = await Lg.i.read(change.previous);
        final real = await Lg.i.read(inventory.getItem(slot: index));
        if (!previous.sameItemSameComponents(real)) {
          await _setSlotHostAsync(
            player,
            change.slot,
            inventory.getItem(slot: index),
          );
          continue;
        }
        final count = await change.stack.getCount();
        await inventory.setItem(
          slot: index,
          item: count <= 0 ? null : change.stack,
        );
      }
    } finally {
      inventory.dispose();
    }
    if (ghostChanged) await session.save();
  }

  /// `create:submit_ghost_item` for a filter screen (a JEI drag onto a ghost slot).
  static Future<void> submitGhost(Player player, int slot, LStack stack) async {
    final session = get(player);
    if (session == null) return;
    if (!session.setGhost(slot, stack)) return;
    await session.save();
    await _sendGhosts(player, session);
  }

  /// Sends the session's ghost slots to the open menu.
  static Future<void> _sendGhosts(Player player, FilterMenuSession session) async {
    for (var i = 0; i < session.ghostItems.length; i++) {
      if (session.kind == FilterMenuKind.attribute && i == attributeDisplaySlot) {
        continue;
      }
      await _setSlotAsync(
        player,
        ghostMenuPlayerSlots + i,
        session.ghostItems[i],
      );
    }
  }

  /// The stack of the player inventory slot behind menu slot [menuSlot]
  /// (`MenuBase.addPlayerSlots`: the main inventory 9 to 35, then the hotbar 0 to 8).
  static Future<LStack> _playerStack(Player player, int menuSlot) async {
    final index = inventoryIndexAt(menuSlot);
    if (index == null) return LStack.empty;
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      return await Lg.i.read(inventory.getItem(slot: index));
    } finally {
      inventory.dispose();
    }
  }

  static Future<LStack> _hotbarStack(Player player, int hotbar) async {
    if (hotbar < 0 || hotbar > 8) return LStack.empty;
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      return await Lg.i.read(inventory.getItem(slot: hotbar));
    } finally {
      inventory.dispose();
    }
  }

  /// `HeldItemGhostItemMenu.stillValid`: the screen belongs to the selected hotbar slot and the
  /// item is still the filter it edits. The client closes its screen on a change too.
  static Future<bool> _isStillValid(
    Player player,
    FilterMenuSession session,
  ) async {
    final target = session.target;
    if (target is! HeldFilterTarget) return true;
    if (player.getSelectedSlot() != target.slot) return false;
    final held = await _playerStack(
      player,
      playerMenuSlotOf(target.slot),
    );
    return held.isNotEmpty && held.key == session.current.key;
  }

  /// The session of the screen the player has open. The payloads act on the open screen only
  /// (`player.containerMenu instanceof FilterMenu` in Java), so a packet that arrives with no
  /// filter screen open is ignored instead of editing a filter the player only looks at.
  static Future<FilterMenuSession?> resolve(Player player) async {
    final open = get(player);
    if (open != null) return open;

    // `create:clear_container` is shared with the blueprint and linked-controller screens.
    final menu = player.currentPluginMenu;
    if (menu == null || FilterMenuKind.ofMenuType(menu.menuType) == null) {
      return null;
    }

    // The screen is open but the session was lost (a plugin reload): rebuild it from the held
    // filter item, the stack the screen edits.
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      final slot = player.getSelectedSlot();
      final held = inventory.getItem(slot: slot);
      if (held == null) return null;
      final stack = await Lg.i.read(held);
      if (FilterMenuKind.of(stack.key) == null) return null;
      return FilterMenuSession.fromStack(stack, HeldFilterTarget(player, slot));
    } finally {
      inventory.dispose();
    }
  }
}

List<int> _varInt(int value) {
  final out = <int>[];
  var v = value;
  while (v & ~0x7F != 0) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}
