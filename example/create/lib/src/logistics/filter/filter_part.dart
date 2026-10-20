// The filter items (`AllItems.FILTER`, `ATTRIBUTE_FILTER`, `PACKAGE_FILTER`) and the item
// attribute registry they use (`AllItemAttributeTypes`). The part also routes the value settings
// board (`create:value_settings`) to the filter slots of this module and handles the filter screen
// payloads (`create:configure_filter`, `create:clear_container`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../api/fluids.dart';
import '../../api/payloads.dart' show ItemStackData;
import '../../api/processing.dart';
import '../../api/value_settings.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/registry.dart';
import '../../data/datapack.g.dart' show datapackBlobs;
import '../factory/factory_panel_block_entity.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/stack.dart';
import 'filter_api.dart';
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
    // The `ItemFilterApi` adapter decodes a list filter's ghost slots with the runtime's wire
    // (the server's component ids).
    ItemFilterApiAdapter.wire = () => rt.wire;
    // Tags are the host's; the attribute filter asks through the hook.
    ItemAttributeHooks.itemInTag = (itemKey, tag) => Tags.item(itemKey, tag);
    // The host can test a tag but not list the tags of an item, so the candidates are the item
    // tags of the shipped data pack (see [itemTagCandidates]).
    ItemAttributeHooks.tagsOf = (itemKey) => [
      for (final tag in itemTagCandidates())
        if (Tags.item(itemKey, tag)) tag,
    ];
    // `ItemContainerContents.STREAM_CODEC`: the ghost slots of a shulker box.
    ItemAttributeHooks.containerContents = (bytes) {
      try {
        return PacketBuffer.decode(bytes, rt.wire.readContents);
      } on Object {
        return null;
      }
    };
    _installProcessingHooks(ctx);
    _installFluidHooks();

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

    // The filter screen mirrors the player inventory and its ghost slots, so the plugin applies
    // the ghost clicks (`GhostItemMenu.clicked` / `quickMoveStack`) and writes the player
    // inventory mirror back.
    ctx.host.intercept(Events.menuClick, (server, e) async {
      if (FilterMenuKind.ofMenuType(e.menuType) == null) return e;
      final handled = await FilterMenuSessions.handleClick(e.player, e);
      return handled ? e.copyWith(cancelled: true) : e;
    });
    ctx.listen(Events.menuSlotChanged, (server, e) {
      if (FilterMenuKind.ofMenuType(e.menuType) == null) return;
      unawaited(FilterMenuSessions.handleSlotChanged(e.player, e));
    });

    // `GhostItemSubmitPacket` of a filter screen (a JEI drag onto a ghost slot). The schedule and
    // stock keeper screens handle their own slots on the same channel.
    rt.bus.onServerbound('create:submit_ghost_item', (player, fields) {
      final menu = player.currentPluginMenu;
      if (menu == null || FilterMenuKind.ofMenuType(menu.menuType) == null) return;
      final slot = fields['slot'] as int? ?? -1;
      final item = fields['item'];
      final stack = item is ItemStackData ? rt.wire.fromData(item) : LStack.empty;
      unawaited(FilterMenuSessions.submitGhost(player, slot, stack));
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
      // `BlockEntityConfigurationPacket.handle`.
      if (player.isSpectator || player.isAdventure) return;
      final pos = fields['pos'] as Pos;
      final worldId = rt.playerWorldId(player);
      if (!player.getWorld().isLoaded(pos: pos.toBlockPos())) return;
      final be = rt.store.at(worldId, pos.toBlockPos());
      if (be == null) return;

      final index = fields['behaviourIndex'] as int? ?? 0;
      ValueSettingsTarget? target;
      if (be is FactoryPanelBlockEntity) {
        // `ValueSettingsPacket.applySettings` matches the behaviour's `netId()`, which a factory
        // gauge reports as `2 + slot.ordinal()` (`FactoryPanelBehaviour.java:1069-1071`).
        for (final panel in be.panels.values) {
          if (panel.netId == index) {
            target = panel;
            break;
          }
        }
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

  @override
  void onServerLoaded(CreateRuntime runtime, LgRuntime rt) {
    // `AllItemAttributeTypes.maxEnchanted` needs the maximum level of every enchantment; the
    // manager lists them, so the map is filled once the server exists.
    unawaited(_loadEnchantmentLevels(runtime.server));
  }

  static Future<void> _loadEnchantmentLevels(Server server) async {
    try {
      final manager = server.getEnchantmentManager();
      final ids = await manager.ids();
      final levels = <String, int>{};
      for (final id in ids) {
        final definition = await manager.find(id);
        if (definition != null) levels[id] = definition.maxLevel;
      }
      ItemAttributeHooks.enchantmentMaxLevels = levels;
    } on Object {
      // a server that cannot list its enchantments leaves `max_enchanted` without an answer
    }
  }

  /// `AllItemAttributeTypes.testRecipe`: the recipe lookups of the single-input types. The
  /// processing module owns the recipes; a server without it (module disabled) answers "no".
  void _installProcessingHooks(CreateContext ctx) {
    final book = ctx.services.find<RecipeBook>();
    if (book == null) return;
    bool create(CreateRecipeType type, LStack stack) =>
        book.findForInput(type, PStack(stack.key, stack.count)) != null;
    bool cooking(List<CookingEntry> recipes, LStack stack) =>
        FanCookingCache.firstOf(
          recipes,
          PStack(stack.key, stack.count),
          book.tags,
        ) !=
        null;
    final cache = FanCookingCache.current;
    ItemAttributeHooks.hasRecipe = (recipeType, stack) => switch (recipeType) {
      'create:splashing' => create(CreateRecipeType.splashing, stack),
      'create:haunting' => create(CreateRecipeType.haunting, stack),
      'create:crushing' => create(CreateRecipeType.crushing, stack),
      'create:milling' => create(CreateRecipeType.milling, stack),
      'minecraft:smelting' => cache != null && cooking(cache.smelting, stack),
      'minecraft:smoking' => cache != null && cooking(cache.smoking, stack),
      'minecraft:blasting' => cache != null && cooking(cache.blasting, stack),
      _ => false,
    };
  }

  /// The fluid contents of an item (`GenericItemEmptying`), for `has_fluid` and for the fluid a
  /// plain filter item stands for (`FilterItemStack.resolveFluid`).
  void _installFluidHooks() {
    if (!FluidsRuntime.isLoaded) return;
    final rules = FluidsRuntime.instance.rules;
    final emptying = GenericItemEmptying(rules);
    String? fluidOf(LStack stack) {
      final spec = FluidItemSpec(stack.key, stack.count);
      if (!emptying.canItemBeEmptied(spec)) return null;
      final (fluid, _, _) = emptying.emptyItem(spec, simulate: true);
      return fluid.isEmpty ? null : FluidKeys.still(fluid.fluid);
    }

    ItemAttributeHooks.fluidOf = fluidOf;
    ItemAttributeHooks.holdsFluid = (stack) =>
        emptying.canItemBeEmptied(FluidItemSpec(stack.key, stack.count));
    FilterItemStack.filterFluid = fluidOf;
  }
}

/// The item tag names the shipped data pack declares (`data/<ns>/tags/item/**.json`).
///
/// The host can answer "is this item in that tag" but not "which tags has this item": Java reads
/// the item's tag set (`InTagAttribute.Type`). The pack's own tags are the names this process can
/// know, so `in_tag` is offered for those; a vanilla tag the pack does not mention (for example
/// `minecraft:logs`) is still matched when a filter names it, but is not offered in the menu.
List<String> itemTagCandidates() => _itemTagCandidates ??= _readItemTagCandidates();

List<String>? _itemTagCandidates;

List<String> _readItemTagCandidates() {
  final names = <String>{};
  for (final blob in datapackBlobs) {
    if (blob.category != 'tags') continue;
    for (final file in blob.unpack()) {
      // data/<namespace>/tags/item/<path>.json
      final parts = file.path.split('/');
      if (parts.length < 5 || parts[0] != 'data' || parts[2] != 'tags') continue;
      if (parts[3] != 'item' || !file.path.endsWith('.json')) continue;
      final path = parts.sublist(4).join('/');
      names.add('${parts[1]}:${path.substring(0, path.length - '.json'.length)}');
    }
  }
  return names.toList()..sort();
}
