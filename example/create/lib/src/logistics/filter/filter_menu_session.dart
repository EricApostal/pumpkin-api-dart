// The server side of the filter screens (`FilterMenu`, `AttributeFilterMenu`,
// `PackageFilterMenu`). The host does not expose the state of a mod menu that a Create client
// opened (`Menus.getOpenMenu` only reports plugin menus), so the plugin keeps the filter state
// itself and applies the `create:configure_filter` / `create:clear_container` payloads to it.
//
// The edited stack is either the filter item in the player's hand (the normal case: using a
// filter item opens its screen) or the filter item in a block entity's filter slot (the block
// entity the player is looking at). Every change is written back at once, so the server state
// and the client's copy stay in step even though no Java menu saves it on close.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart' hide ItemAttribute;
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../core/nbt.dart';
import '../host/runtime.dart';
import '../model/package.dart';
import '../model/stack.dart';
import 'filter_item_stack.dart';
import 'filtering_behaviour.dart';
import 'item_attribute.dart';

/// Which filter screen is open.
enum FilterMenuKind {
  list('create:filter'),
  attribute('create:attribute_filter'),
  package('create:package_filter');

  const FilterMenuKind(this.menuType);

  final String menuType;

  static FilterMenuKind? of(String filterItemKey) => switch (filterItemKey) {
    FilterItemKeys.list => list,
    FilterItemKeys.attribute => attribute,
    FilterItemKeys.package => package,
    _ => null,
  };

  static FilterMenuKind? ofMenuType(String menuType) {
    for (final kind in values) {
      if (kind.menuType == menuType) return kind;
    }
    return null;
  }
}

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

/// The filter item in a block entity's filter slot (`FilteringBehaviour`).
final class BehaviourFilterTarget implements FilterTarget {
  final FilteringBehaviour behaviour;

  const BehaviourFilterTarget(this.behaviour);

  @override
  Future<void> write(LStack filter) async {
    behaviour.setFilter(filter);
  }

  @override
  void dispose() {}
}

/// One open filter screen: its kind, the target and the editable state.
final class FilterMenuSession {
  final FilterMenuKind kind;
  final FilterTarget target;

  /// The container id of the open screen, `-1` until it was opened.
  int containerId = -1;

  /// The filter stack the session started from (other components are preserved).
  final LStack current;

  /// `GhostItemMenu.ghostInventory`: 18 slots for a list filter.
  final List<LStack> ghostItems = List<LStack>.filled(
    18,
    LStack.empty,
    growable: false,
  );

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
    final int containerId;
    try {
      containerId = player.openPluginMenu(
        kind.menuType,
        'Filter',
        extraData: extra,
      );
    } on Object catch (e) {
      // A Bedrock player, an unknown menu type or a closed registration.
      Lg.i.log.warn('Could not open ${kind.menuType}: $e');
      heldTarget.dispose();
      return;
    }
    session.containerId = containerId;
    // A session that was still open is replaced (its changes were already written by every
    // configure packet).
    _byPlayer.remove(player.getId().asString)?.dispose();
    put(player, session);
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

  /// The open session, or one built from the filter item the player edits: the filter slot of
  /// the block entity they look at, else the filter item in their hand.
  static Future<FilterMenuSession?> resolve(Player player) async {
    final open = get(player);
    if (open != null) return open;

    // `create:clear_container` is shared with the blueprint and linked-controller screens. Those
    // are plugin menus of other types, so their packets must not reach a held filter item.
    final menu = player.currentPluginMenu;
    if (menu != null && FilterMenuKind.ofMenuType(menu.menuType) == null) {
      return null;
    }

    final hit = player.getTargetBlockExact(
      maxDistance: 6,
      includeFluids: false,
    );
    if (hit != null) {
      final be = Lg.i.store.at(Lg.i.playerWorldId(player), hit.pos);
      final behaviour = be?.getBehaviour<FilteringBehaviour>();
      final filter = behaviour?.filter;
      if (behaviour != null && filter != null && filter.isFilterItem) {
        return FilterMenuSession.fromStack(
          filter.item,
          BehaviourFilterTarget(behaviour),
        );
      }
    }

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
