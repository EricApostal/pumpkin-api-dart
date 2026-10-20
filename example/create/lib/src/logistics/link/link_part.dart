// The stock link block and the part that registers it (`PackagerLinkBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../stock/stock_ticker_block_entity.dart';
import 'linked_item.dart';
import 'packager_link_block_entity.dart';

/// The items whose network is stored in `minecraft:block_entity_data`
/// (`LogisticallyLinkedBlockItem` and `FactoryPanelBlockItem`).
const Set<String> _linkedItemKeys = {
  'create:stock_link',
  'create:stock_ticker',
  'create:redstone_requester',
  'create:factory_gauge',
};

/// `LogisticallyLinkedBlockItem.use` / `useOn`: a tuned item clears its network when used in the
/// air, and copies the network of the link it is used on.
Future<PlayerUseItemEventData> _onLinkedItemUse(
  Server server,
  PlayerUseItemEventData e,
) async {
  final rt = Lg.i;
  final inventory = e.player.getInventory();
  try {
    final held = inventory.getItemInHand(hand: e.hand);
    if (held == null) return e;
    final stack = await rt.read(held);
    if (!_linkedItemKeys.contains(stack.key)) return e;
    final worldId = rt.playerWorldId(e.player);

    final clicked = e.clickedPos;
    if (clicked != null) {
      // `useOn`: a clicked link gives its frequency to the item.
      final be = rt.store.at(worldId, clicked);
      final LogisticallyLinkedBehaviour? link = switch (be) {
        final PackagerLinkBlockEntity link => link.behaviour,
        final StockCheckingBlockEntity checking => checking.behaviour,
        _ => null,
      };
      if (link == null) return e;
      if (!link.mayInteract(e.player.getId().asString)) return e.cancel();
      final host = await rt.write(
        LinkedItem.assignFrequency(stack, link.freqId),
      );
      if (host != null) {
        await inventory.setItemInHand(hand: e.hand, item: host);
      }
      e.player.showActionbar(
        text: TextComponent.translate(
          key: 'create.logistically_linked.tuned',
          with_: const [],
        ),
      );
      return e.cancel();
    }

    if (!LinkedItem.isTuned(stack)) return e;
    final host = await rt.write(LinkedItem.clearTuning(stack));
    if (host != null) {
      await inventory.setItemInHand(hand: e.hand, item: host);
    }
    e.player.showActionbar(
      text: TextComponent.translate(
        key: 'create.logistically_linked.cleared',
        with_: const [],
      ),
    );
    rt.world(worldId)?.playSound(
      sound: Sound.entityItemFrameRemoveItem,
      category: SoundCategory.blocks,
      pos: e.player.getPosition(),
      volume: 0.75,
      pitch: 1,
    );
    return e.cancel();
  } finally {
    inventory.dispose();
  }
}

/// `PackagerLinkBlock`.
CreateBlock stockLinkBlock() => CreateBlock(
  key: 'create:stock_link',
  properties: [
    attachFaceProperty,
    horizontalFacingProperty,
    CreateProps.powered,
    CreateProps.waterlogged,
  ],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  blockEntityType: PackagerLinkBlockEntity.type,
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onPlaced: _onPlaced,
  ),
);

Future<void> _onNeighborUpdate(
  Server server,
  CustomBlockNeighborUpdateEventData e,
) async {
  final be = Lg.i.store.typed<PackagerLinkBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  await be.refreshPower();
}

Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final be = Lg.i.store.typed<PackagerLinkBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;
  be.placedBy = uuid;
  be.notifyUpdate();
}

/// The `packager_link` part.
final class LinkPart extends LogisticsPart {
  @override
  String get name => 'link';

  @override
  void register(CreateRegistry registry) {
    registry.block(stockLinkBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: PackagerLinkBlockEntity.type,
        validBlocks: ['create:stock_link'],
        create: PackagerLinkBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // The global logistics data is loaded with the overworld (see the module).
    unawaited(Future<void>.value());
    // `LogisticallyLinkedBlockItem`'s clear / copy network interaction.
    ctx.host.intercept(Events.playerUseItem, _onLinkedItemUse);
  }
}
