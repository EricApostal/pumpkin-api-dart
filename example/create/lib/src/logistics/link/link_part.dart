// The stock link block and the part that registers it (`PackagerLinkBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/link_keys.dart';
import '../host/runtime.dart';
import '../host/state_props.dart';
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
  mapColor: manifestMapColor('stock_link'),
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
  // `PackagerLinkBlock.getStateForPlacement` needs the clicked face and the look, which a
  // placement rule cannot map to `face`/`facing`: [onCanPlace] computes the real state. The rule
  // is the fallback for a placement the hook does not see (like the factory gauge's).
  placement: const [PlacementRule.horizontalFacing('facing')],
  blockEntityType: PackagerLinkBlockEntity.type,
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onCanPlace: _onCanPlace,
    onPlaced: _onPlaced,
  ),
);

/// A stock link placement computed from the clicked face, kept until the `player-placed` event
/// (the host has no state-for-placement hook).
final Map<String, _LinkPlacement> _pendingLinkPlacements = {};

final class _LinkPlacement {
  final BState state;
  final String player;

  const _LinkPlacement(this.state, this.player);
}

String _linkPlacementKey(World world, Pos pos) =>
    '${world.getId()}:${pos.$1},${pos.$2},${pos.$3}';

Direction _dirOf(BlockDirection d) => Direction.values[d.index];

/// `PackagerLinkBlock.getStateForPlacement`: `FaceAttachedHorizontalDirectionalBlock`'s first
/// nearest-looking direction (the direction towards the clicked block first), `FACING` turned
/// around for a link hanging from a ceiling. `canSurvive` is always true for the link, so the
/// first candidate always wins; `POWERED` is added by [refreshPower] once the block is there.
BState _linkStateForPlacement(
  World world,
  Pos pos,
  Player player,
  Direction support,
) =>
    faceAttachedStateForPlacement(
      'create:stock_link',
      look: player.lookDirection,
      yaw: player.getYaw(),
      towardsClicked: support,
      // `PackagerLinkBlock.canSurvive` accepts every position.
      canAttach: (_) => true,
      waterlogged: replacesWater(world, pos),
      adjust: (state) => state['face'] == 'ceiling'
          ? state.setDir('facing', state.dir('facing')!.opposite)
          : state,
    )!;

Future<bool> _onCanPlace(Server server, CustomBlockCanPlaceEventData e) async {
  if (!e.canPlace || e.player == null || e.face == null) return e.canPlace;
  final player = Lg.i.player(e.player!.asString);
  if (player == null) return true;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  _pendingLinkPlacements[_linkPlacementKey(world, pos)] = _LinkPlacement(
    _linkStateForPlacement(world, pos, player, _dirOf(e.face!)),
    e.player!.asString,
  );
  return true;
}

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

/// `PackagerLinkBlock.setPlacedBy`: remembers the placer and fixes the state the host placed
/// (which the stock link's placement rules cannot express).
Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  final uuid = e.player?.asString;
  if (uuid == null) return;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final be = Lg.i.store.typed<PackagerLinkBlockEntity>(world.getId(), e.pos);
  if (be == null) return;

  final pending = _pendingLinkPlacements.remove(_linkPlacementKey(world, pos));
  if (pending != null && pending.player == uuid) {
    final info = BlockStates.info(world.getBlockStateId(pos: e.pos));
    if (info?.key == 'create:stock_link') {
      final current = BState('create:stock_link', info!.properties);
      final differs =
          current.props.length != pending.state.props.length ||
          current.props.entries.any(
            (entry) => pending.state.props[entry.key] != entry.value,
          );
      if (differs) await setBlockState(world, pos, pending.state);
    }
  }

  be.placedBy = uuid;
  be.notifyUpdate();
  await be.refreshPower();
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
