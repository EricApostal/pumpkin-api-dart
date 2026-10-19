// The server side of `FactoryPanelSetItemMenu`: the ghost item slot that lets a player set a
// gauge's filter (from JEI or with an empty hand). The Create client owns the screen and the
// ghost inventory; the host only sees a generic menu, so the plugin mirrors the ghost slot from
// the click and applies it when the screen closes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/module.dart';
import '../host/runtime.dart';
import '../model/stack.dart';
import 'factory_panel_behaviour.dart';
import 'factory_panel_block_entity.dart';

/// `AllMenuTypes.FACTORY_PANEL_SET_ITEM`.
const String factoryPanelSetItemMenuType = 'create:factory_panel_set_item';

/// The ghost slot index of `FactoryPanelSetItemMenu` (36 player slots, then the ghost slot).
const int factoryPanelGhostSlot = 36;

final class FactoryPanelSetItemSession {
  final FactoryPanelPosition position;
  final int containerId;
  LStack stack = LStack.empty;

  FactoryPanelSetItemSession(this.position, this.containerId);
}

/// The open set-item menus, by player uuid.
abstract final class FactoryPanelSetItemMenus {
  static final Map<String, FactoryPanelSetItemSession> _byPlayer = {};

  /// The `extraData` of `FactoryPanelPosition.STREAM_CODEC`: the packed position and the slot
  /// ordinal.
  static List<int> encodePosition(FactoryPanelPosition position) =>
      PacketBuffer.encode((w) {
        w.writeLong(position.pos.asLong);
        w.writeVarInt(position.slot.index);
      });

  /// `ServerPlayer.openMenu(this, buf -> FactoryPanelPosition.STREAM_CODEC.encode(buf, pos))`.
  static void open(Player player, FactoryPanelPosition position) {
    final int containerId;
    try {
      containerId = player.openPluginMenu(
        factoryPanelSetItemMenuType,
        'Factory Gauge',
        extraData: encodePosition(position),
        slots: factoryPanelGhostSlot + 1,
      );
    } on Object catch (e) {
      Lg.i.log.warn('Could not open $factoryPanelSetItemMenuType: $e');
      return;
    }
    _byPlayer[player.getId().asString] = FactoryPanelSetItemSession(
      position,
      containerId,
    );
  }

  static void install(CreateContext ctx, LgRuntime rt) {
    ctx.host.intercept(Events.menuClick, (server, e) async {
      if (e.menuType != factoryPanelSetItemMenuType) return e;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return e;
      if (e.slot != factoryPanelGhostSlot) return e;

      // `GhostItemMenu.clicked`: the ghost slot takes one item off the cursor and never consumes
      // the player's stack.
      final carried = await rt.read(e.cursorStack);
      session.stack = carried.isEmpty ? LStack.empty : carried.withCount(1);
      return e.cancel();
    });

    ctx.listen(Events.menuSlotChanged, (server, e) async {
      if (e.menuType != factoryPanelSetItemMenuType) return;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return;
      for (final change in e.changes) {
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
