// The server side of `FactoryPanelSetItemMenu`: the ghost item slot that lets a player set a
// gauge's filter (from JEI or with an empty hand). The Create client owns the screen and the
// ghost inventory; the host only sees a generic menu, so the plugin mirrors the ghost slot from
// the click and applies it when the screen closes.
import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../common/ghost_menu_layout.dart';
import '../../common/ghost_quick_move.dart';
import '../../common/host_bridge.dart';
import '../../common/menu_mirror.dart';
import '../../common/pos.dart';
import '../../core/module.dart';
import '../host/runtime.dart';
import '../model/stack.dart';
import 'factory_panel_behaviour.dart';
import 'factory_panel_block_entity.dart';

/// `AllMenuTypes.FACTORY_PANEL_SET_ITEM`.
const String factoryPanelSetItemMenuType = 'create:factory_panel_set_item';

/// `FactoryPanelSetItemMenu.addSlots`: the 36 player slots first, then the gauge filter slot.
const GhostMenu factoryPanelLayout = GhostMenu.factoryPanelSetItem;

/// The ghost slot index of `FactoryPanelSetItemMenu` (36 player slots, then the ghost slot).
final int factoryPanelGhostSlot = factoryPanelLayout.ghostSlot(0);

final class FactoryPanelSetItemSession {
  final FactoryPanelPosition position;
  final int containerId;
  LStack stack = LStack.empty;

  FactoryPanelSetItemSession(this.position, this.containerId);
}

/// The open set-item menus, by player uuid.
abstract final class FactoryPanelSetItemMenus {
  static final Map<String, FactoryPanelSetItemSession> _byPlayer = {};

  /// The click rules of the screen: the ghost slot takes one item off the cursor
  /// (`GhostItemMenu.clicked`; `FactoryPanelSetItemMenu.allowRepeats()`).
  static final MenuClickRules _rules = MenuClickRules(
    slotRules: [
      MenuSlotRule(
        slot: factoryPanelGhostSlot,
        kind: const MenuSlotKindGhost(),
        maxStackSize: 1,
      ),
    ],
    quickMoveTargets: const [],
  );

  /// The `extraData` of `FactoryPanelPosition.STREAM_CODEC`: the packed position and the slot
  /// ordinal.
  static List<int> encodePosition(FactoryPanelPosition position) =>
      PacketBuffer.encode((w) {
        w.writeLong(position.pos.asLong);
        w.writeVarInt(position.slot.index);
      });

  /// `ServerPlayer.openMenu(this, buf -> FactoryPanelPosition.STREAM_CODEC.encode(buf, pos))`.
  static Future<void> open(Player player, FactoryPanelPosition position) async {
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: factoryPanelSetItemMenuType,
      title: Messages.component('Factory Gauge'),
      extraData: encodePosition(position),
      slotCount: factoryPanelLayout.menuSlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first (`FactoryPanelSetItemMenu.addSlots`),
        // so the server tracks a mirror of it instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules,
      ),
    );
    if (result is! OkResult<int, String>) {
      Lg.i.log.warn(
        'Could not open $factoryPanelSetItemMenuType: '
        '${(result as ErrorResult<int, String>).value}',
      );
      return;
    }
    _byPlayer[player.getId().asString] = FactoryPanelSetItemSession(
      position,
      result.value,
    );
    // The mirror of the player inventory the client's menu shows first.
    await fillPlayerMirror(player);
  }

  static void install(CreateContext ctx, LgRuntime rt) {
    // The host applies the vanilla clicks (the player inventory mirror and the ghost slot; the
    // ghost slot takes one item off the cursor). The shift-clicks follow
    // `GhostItemMenu.quickMoveStack` and are applied here: one item of a mirror slot goes into the
    // gauge filter, one item leaves it.
    ctx.host.intercept(Events.menuClick, (server, e) async {
      if (e.menuType != factoryPanelSetItemMenuType) return e;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return e;
      if (e.mode != MenuClickMode.quickMove) return e;
      final move = ghostQuickMove(
        menuSlot: e.slot,
        source: await rt.read(await playerStackAt(e.player, e.slot)),
        ghostSlots: factoryPanelLayout.ghostSlots,
        ghostEmpty: (i) => session.stack.isEmpty,
      );
      if (!move.isNone) {
        session.stack = move.take
            ? (session.stack.count > 1 ? session.stack.withCount(session.stack.count - 1) : LStack.empty)
            : move.stack;
        await setMenuSlot(e.player, factoryPanelGhostSlot, await rt.write(session.stack));
      }
      return e.copyWith(cancelled: true);
    });

    ctx.listen(Events.menuSlotChanged, (server, e) async {
      if (e.menuType != factoryPanelSetItemMenuType) return;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return;
      for (final change in e.changes) {
        // The player inventory mirror is written back to the real inventory.
        if (await applyPlayerMirrorChange(e.player, change)) continue;
        if (change.slot != factoryPanelGhostSlot) continue;
        session.stack = await rt.read(change.stack);
      }
    });

    ctx.listen(Events.menuClosed, (server, e) {
      if (e.menuType != factoryPanelSetItemMenuType) return;
      final session = _byPlayer.remove(e.player.getId().asString);
      if (session == null) return;
      if (session.containerId != e.containerId) return;

      final be = rt.store.typed<FactoryPanelBlockEntity>(
        rt.playerWorldId(e.player),
        session.position.pos.toBlockPos(),
      );
      final behaviour = be?.panels[session.position.slot];
      behaviour?.setFilter(session.stack);
    });
  }

  /// Forgets a player (disconnect).
  static void forget(String playerUuid) => _byPlayer.remove(playerUuid);
}
