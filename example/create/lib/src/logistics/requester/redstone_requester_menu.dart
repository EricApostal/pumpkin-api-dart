// The server side of `RedstoneRequesterMenu`: the screen the redstone requester opens
// (`RedstoneRequesterBlockEntity.use`). Java opens it with the block position as extra data and
// nine ghost slots the client edits (the request's items); the items come back through the ghost
// slots at close (`RedstoneRequesterMenu.saveData`) while the address, the amounts and
// `allowPartial` arrive as `create:configure_redstone_requester`.
//
// `RedstoneRequesterMenu.addSlots` adds the 36 player slots **before** the nine ghost slots, so the
// client's menu indices are the player inventory first (`GhostItemMenu.clicked` tests `slotId < 36`).
// The host's plugin menus put their own slots first, so this opens the menu with the client's
// layout and mirrors the player inventory into the first 36 slots, like the filter screens do.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, rules, cursor) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../common/ghost_quick_move.dart';
import '../../common/menu_mirror.dart' show playerStackAt;
import '../../core/module.dart';
import '../../core/pos.dart' show packPos;
import '../filter/filter_menu_clicks.dart' show ghostMenuPlayerSlots, inventoryIndexAt;
import '../host/runtime.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import 'redstone_requester_block_entity.dart';

/// `AllMenuTypes.REDSTONE_REQUESTER`.
const String redstoneRequesterMenuType = 'create:redstone_requester';

/// The 36 player slots the client's menu adds first (`RedstoneRequesterMenu.addSlots`).
const int requesterPlayerSlots = ghostMenuPlayerSlots;

/// `createGhostInventory().getSlots()`.
const int requesterGhostSlots = 9;

/// The number of slots the client's menu has.
const int requesterMenuSlots = requesterPlayerSlots + requesterGhostSlots;

/// A requester screen that is open for one player, with the mirror of their inventory and the
/// ghost slots the client edits.
final class RedstoneRequesterSession {
  final String worldId;
  final BlockPos pos;
  final int containerId;

  /// The ghost slots (`ghostInventory`), filled from the block entity when the menu opens.
  final List<LStack> ghosts;

  RedstoneRequesterSession(this.worldId, this.pos, this.containerId, this.ghosts);
}

abstract final class RedstoneRequesterMenus {
  static final Map<String, RedstoneRequesterSession> _byPlayer = {};

  static RedstoneRequesterSession? get(Player player) =>
      _byPlayer[player.getId().asString];

  static final MenuClickRules _rules = MenuClickRules(
    slotRules: [
      for (var i = 0; i < requesterGhostSlots; i++)
        MenuSlotRule(
          slot: requesterPlayerSlots + i,
          kind: const MenuSlotKindGhost(),
          maxStackSize: 1,
        ),
    ],
    quickMoveTargets: const [],
  );

  /// `ServerPlayer.openMenu(this, worldPosition)`: the extra data is the block position
  /// (`RedstoneRequesterMenuClient.createOnClient` reads it).
  static Future<void> open(
    Player player,
    RedstoneRequesterBlockEntity be,
    String worldId,
  ) async {
    final extra = PacketBuffer.encode(
      (w) => w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z)),
    );
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: redstoneRequesterMenuType,
      // `getDisplayName()` is an empty component.
      title: TextComponent.text(plain: ''),
      extraData: extra,
      slotCount: requesterMenuSlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first, so the server tracks a mirror of it
        // instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules,
      ),
    );
    if (result is! OkResult<int, String>) {
      Lg.i.log.warn(
        'Could not open the redstone requester: ${(result as ErrorResult<int, String>).value}',
      );
      return;
    }
    _byPlayer.remove(player.getId().asString)?.dispose();
    final session = RedstoneRequesterSession(
      worldId,
      be.pos,
      result.value,
      _ghostItemsOf(be),
    );
    _byPlayer[player.getId().asString] = session;
    await _fill(player, session);
    await _sendGhosts(player, session);
  }

  /// `createGhostInventory()`: the request's items, one each.
  static List<LStack> _ghostItemsOf(RedstoneRequesterBlockEntity be) {
    final items = List<LStack>.filled(requesterGhostSlots, LStack.empty);
    final stacks = be.encodedRequest.stacks;
    for (var i = 0; i < stacks.length && i < requesterGhostSlots; i++) {
      final stack = stacks[i].stack;
      items[i] = stack.isEmpty ? LStack.empty : stack.withCount(1);
    }
    return items;
  }

  /// Sends the player inventory mirror and the ghost slots to the client.
  static Future<void> _fill(Player player, RedstoneRequesterSession session) async {
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      for (var menuSlot = 0; menuSlot < requesterPlayerSlots; menuSlot++) {
        final index = inventoryIndexAt(menuSlot);
        if (index == null) continue;
        await _setSlot(player, menuSlot, inventory.getItem(slot: index));
      }
    } finally {
      inventory.dispose();
    }
  }

  static Future<void> _sendGhosts(
    Player player,
    RedstoneRequesterSession session,
  ) async {
    for (var i = 0; i < session.ghosts.length; i++) {
      final host = session.ghosts[i].isEmpty
          ? null
          : await Lg.i.write(session.ghosts[i]);
      try {
        if (host == null) {
          player.clearPluginMenuSlot(requesterPlayerSlots + i);
        } else {
          player.setPluginMenuSlot(requesterPlayerSlots + i, host);
        }
      } on Object {
        // the menu closed meanwhile
      } finally {
        host?.dispose();
      }
    }
  }

  static Future<void> _setSlot(
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

  /// `Events.menuSlotChanged`: the player inventory mirror is written back to the real inventory,
  /// the ghost slots the host changed (a cursor click) into the session.
  static Future<void> handleSlotChanged(
    Player player,
    MenuSlotChangedEventData e,
  ) async {
    final session = get(player);
    if (session == null || e.containerId != session.containerId) return;
    var ghostsChanged = false;
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    playerInventory.dispose();
    try {
      for (final change in e.changes) {
        if (change.slot >= requesterPlayerSlots) {
          final index = change.slot - requesterPlayerSlots;
          if (index < 0 || index >= requesterGhostSlots) continue;
          session.ghosts[index] = await Lg.i.read(change.stack);
          ghostsChanged = true;
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
          await _setSlot(player, change.slot, inventory.getItem(slot: index));
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
    if (ghostsChanged) await _sendGhosts(player, session);
  }

  /// `Events.menuClosed`: `RedstoneRequesterMenu.saveData` writes the request back from the ghost
  /// inventory, then the block entity tells its clients.
  static Future<void> close(Player player, int containerId) async {
    final session = _byPlayer.remove(player.getId().asString);
    if (session == null || session.containerId != containerId) return;
    final be = Lg.i.store.typed<RedstoneRequesterBlockEntity>(
      session.worldId,
      session.pos,
    );
    if (be == null) return;
    final stacks = be.encodedRequest.stacks;
    final list = <BigStack>[];
    for (var i = 0; i < session.ghosts.length; i++) {
      final stack = session.ghosts[i];
      if (stack.isEmpty) continue;
      final count = i < stacks.length ? stacks[i].count : 1;
      list.add(BigStack(stack.withCount(1), count));
    }
    var request = PackageOrderWithCrafts(
      PackageOrder(list),
      be.encodedRequest.orderedCrafts,
    );
    if (!request.orderedStacksMatchOrderedRecipes()) {
      request = PackageOrderWithCrafts.simple(request.stacks);
    }
    be.encodedRequest = request;
    be.sendData();
  }

  static void forget(Player player) =>
      _byPlayer.remove(player.getId().asString)?.dispose();

  /// Wires the screen up: the mirror write-back, the ghost slots and the close.
  static void install(CreateContext ctx, LgRuntime rt) {
    ctx.host.intercept(Events.menuClick, (server, e) async {
      if (e.menuType != redstoneRequesterMenuType) return e;
      final session = get(e.player);
      if (session == null || session.containerId != e.containerId) return e;
      // The host applies the vanilla clicks (the player inventory mirror and the ghost slots; a
      // ghost slot takes one item off the cursor). The shift-clicks follow
      // `GhostItemMenu.quickMoveStack` and are applied here instead: one item of a mirror slot goes
      // into the first empty request slot, one item leaves a request slot.
      if (e.mode != MenuClickMode.quickMove) return e;
      final move = ghostQuickMove(
        menuSlot: e.slot,
        source: await Lg.i.read(await playerStackAt(e.player, e.slot)),
        ghostSlots: requesterGhostSlots,
        ghostEmpty: (i) => session.ghosts[i].isEmpty,
      );
      if (!move.isNone) {
        final current = session.ghosts[move.ghost];
        session.ghosts[move.ghost] = move.take
            ? (current.count > 1 ? current.withCount(current.count - 1) : LStack.empty)
            : move.stack;
        await _sendGhosts(e.player, session);
      }
      return e.copyWith(cancelled: true);
    });

    ctx.listen(Events.menuSlotChanged, (server, e) {
      if (e.menuType != redstoneRequesterMenuType) return;
      unawaited(handleSlotChanged(e.player, e));
    });

    ctx.listen(Events.menuClosed, (server, e) {
      if (e.menuType != redstoneRequesterMenuType) return;
      unawaited(close(e.player, e.containerId));
    });

    ctx.listen(Events.playerLeave, (server, e) {
      forget(e.player);
    });
  }
}

extension on RedstoneRequesterSession {
  void dispose() {}
}