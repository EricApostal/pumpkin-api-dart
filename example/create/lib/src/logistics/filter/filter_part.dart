// The filter items (`AllItems.FILTER`, `ATTRIBUTE_FILTER`, `PACKAGE_FILTER`) and the item
// attribute registry they use (`AllItemAttributeTypes`). The part also routes the value settings
// board (`create:value_settings`) to the filter slots of this module and handles the filter screen
// payloads (`create:configure_filter`, `create:clear_container`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../api/value_settings.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/registry.dart';
import '../factory/factory_panel_block_entity.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import 'filter_item_stack.dart';
import 'filter_menu_session.dart';
import 'filtering_behaviour.dart';
import 'item_attribute.dart';

/// The `filter` part.
final class FilterPart extends LogisticsPart {
  @override
  String get name => 'filter';

  @override
  void register(CreateRegistry registry) {
    registry.item(const ItemRegistration(key: FilterItemKeys.list));
    registry.item(const ItemRegistration(key: FilterItemKeys.attribute));
    registry.item(const ItemRegistration(key: FilterItemKeys.package));
    // `AllItems.SHOPPING_LIST` (a table cloth item) is registered last so the item ids follow the
    // manifest order.
    registry.item(
      const ItemRegistration(key: 'create:shopping_list', maxStackSize: 1),
    );

    // `create:item_attribute_type` itself is declared by the content module from the manifest;
    // this fills the registry the filters evaluate against.
    registerDefaultItemAttributes();
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // Tags are the host's; the attribute filter asks through the hook.
    ItemAttributeHooks.itemInTag = (itemKey, tag) => Tags.item(itemKey, tag);

    // `FilterItem.use` / `useOn`: a main-hand use that no block consumed opens the item's screen.
    // The host cannot expose the state of the mod menu, so the plugin tracks the edited filter
    // stack itself (see `filter_menu_session.dart`).
    ctx.listen(Events.playerUseItem, (server, e) async {
      if (e.cancelled) return;
      if (e.hand != Hand.right) return;
      final player = e.player;
      // A block click also sends a use in the air; the screen is already open after the first.
      if (FilterMenuSessions.get(player) != null) return;
      final entity = player.asEntity();
      final sneaking = entity.isSneaking();
      entity.dispose();
      if (sneaking) return;

      final inventory = player.getInventory();
      try {
        final held = inventory.getItemInHand(hand: Hand.right);
        if (held == null) return;
        final stack = await rt.read(held);
        if (FilterMenuKind.of(stack.key) == null) return;
        await FilterMenuSessions.open(
          player,
          stack,
          HeldFilterTarget(player, player.getSelectedSlot()),
        );
      } finally {
        inventory.dispose();
      }
    });

    ctx.listen(Events.menuClosed, (server, e) {
      unawaited(FilterMenuSessions.close(e.player, containerId: e.containerId));
    });
    ctx.listen(Events.playerLeave, (server, e) {
      FilterMenuSessions.forget(e.player);
    });

    // `FilterScreenPacket`.
    rt.bus.onServerbound('create:configure_filter', (player, fields) {
      final option = fields['option'] as int? ?? -1;
      final data = fields['data'];
      unawaited(
        FilterMenuSessions.configure(
          player,
          option,
          data is NbtValue ? data : null,
        ),
      );
    });

    // `ClearMenuPacket`.
    rt.bus.onServerbound('create:clear_container', (player, fields) {
      unawaited(FilterMenuSessions.clear(player));
    });

    // The filter slots (item hatch, table cloth price tag, factory gauges) take values from the
    // value settings board. The redstone module routes its own behaviours; this handler adds the
    // logistics ones (the bus runs every handler of the channel).
    rt.bus.onServerbound('create:value_settings', (player, fields) async {
      final pos = fields['pos'] as Pos;
      final worldId = rt.playerWorldId(player);
      final be = rt.store.at(worldId, pos.toBlockPos());
      if (be == null) return;

      final index = fields['behaviourIndex'] as int? ?? 0;
      final ValueSettingsTarget? target;
      if (be is FactoryPanelBlockEntity) {
        final panels = be.panels.values.toList();
        target = index >= 0 && index < panels.length ? panels[index] : null;
      } else {
        target = be.getBehaviour<FilteringBehaviour>();
      }
      if (target == null) return;

      // `BlockEntityConfigurationPacket`: the player has to be within 20 blocks.
      final (x, y, z) = player.getPosition();
      final dx = x - (pos.$1 + 0.5),
          dy = y - (pos.$2 + 0.5),
          dz = z - (pos.$3 + 0.5);
      if (dx * dx + dy * dy + dz * dz >= 20 * 20) return;

      if (fields['interactHand'] != null) {
        if (target is! FilteringBehaviour) return;
        final inventory = player.getInventory();
        try {
          final held = inventory.getItemInHand(hand: Hand.right);
          if (held == null) return;
          target.interactWith(await rt.read(held));
        } finally {
          inventory.dispose();
        }
        return;
      }

      target.setValueSettings(
        player,
        fields['row'] as int? ?? 0,
        fields['value'] as int? ?? 0,
        ctrlDown: fields['ctrlDown'] == true,
      );
    });
  }
}
