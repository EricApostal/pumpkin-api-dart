// The stock ticker block and the part that registers it, its payload handlers and the stock
// keeper interactions (`StockTickerBlock`, `StockTickerInteractionHandler`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart' show ItemStackData;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../filter/filter_menu_session.dart' show FilterMenuKind;
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../host/link_keys.dart';
import '../link/linked_item.dart';
import '../logistics_part.dart';
import '../model/manager.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import '../requester/auto_request_data.dart';
import 'stock_keeper_menu.dart';
import 'stock_ticker_block_entity.dart';

/// `StockTickerBlock`.
CreateBlock stockTickerBlock() => CreateBlock(
  key: 'create:stock_ticker',
  properties: [horizontalFacingProperty],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'glass',
  blockEntityType: StockTickerBlockEntity.type,
  placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
  behavior: BlockBehavior(onUse: _onUse),
);

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  // `StockTickerBlock.useItemOn`: a `LogisticallyLinkedBlockItem` places itself against the
  // ticker instead of opening the keeper (`create:redstone_requester`).
  final inventory = e.player.getInventory();
  final held = inventory.getItemInHand(hand: Hand.right);
  inventory.dispose();
  if (held != null && await held.getRegistryKey() == 'create:redstone_requester') {
    return BlockUseResult.pass;
  }
  final be = Lg.i.store.typed<StockTickerBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;
  if (!be.behaviour.mayInteract(e.player.getId().asString))
    return BlockUseResult.success;

  // Return the payments of shop trades (the keeper's screen is client side).
  if (be.receivedPayments.nonEmpty().isNotEmpty) {
    for (final stack in be.receivedPayments.nonEmpty()) {
      await giveToPlayer(e.player, stack);
    }
    be.clearPayments();
    return BlockUseResult.success;
  }

  // `StockTickerBlock.useItemOn`: the category screen needs a keeper (a heater or a seated
  // player next to the ticker).
  if (!be.isKeeperPresent) {
    e.player.sendSystemMessage(
      text: TextComponent.translate(
        key: 'create.stock_ticker.keeper_missing',
        with_: const [],
      ),
      overlay: true,
    );
    return BlockUseResult.success;
  }
  await StockKeeperMenus.openCategory(e.player, be);
  return BlockUseResult.success;
}

/// `SeatEntity` of the contraptions module (only its type key is needed here).
const String _seatEntityKey = 'create:seat';

/// `BlockEntityConfigurationPacket.handle`: no spectator or adventure player, the position
/// loaded, and the player within [maxRange] blocks of the block.
bool _mayConfigure(Player player, Pos pos, {int maxRange = 20}) {
  if (player.isSpectator || player.isAdventure) return false;
  if (!player.getWorld().isLoaded(pos: pos.toBlockPos())) return false;
  final (x, y, z) = player.getPosition();
  final dx = x - (pos.$1 + 0.5),
      dy = y - (pos.$2 + 0.5),
      dz = z - (pos.$3 + 0.5);
  return dx * dx + dy * dy + dz * dz < maxRange * maxRange;
}

/// The `stock` part: the stock ticker and the stock keeper payloads.
final class StockPart extends LogisticsPart {
  @override
  String get name => 'stock';

  @override
  void register(CreateRegistry registry) {
    registry.block(stockTickerBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: StockTickerBlockEntity.type,
        validBlocks: ['create:stock_ticker'],
        create: StockTickerBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    final bus = rt.bus;

    // `LogisticalStockRequestPacket`: send the recent summary in chunks. The packet is handled by
    // any stock checking block entity (the stock ticker and the redstone requester) and allows a
    // long range, because the requester screen refreshes its stock list from afar.
    bus.onServerbound('create:logistics_stock_request', (player, fields) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos, maxRange: 4096)) return;
      final be = rt.store.at(rt.playerWorldId(player), pos.toBlockPos());
      if (be is! StockCheckingBlockEntity) return;
      unawaited(_sendStock(player, be));
    });

    // `PackageOrderRequestPacket`: a package order from the stock keeper screen.
    bus.onServerbound('create:logistics_package_request', (player, fields) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos)) return;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      final order = decodeOrder(fields['order']);
      final address = fields['address'] as String? ?? '';
      if (fields['encodeRequester'] == true) {
        // `player.closeContainer()`: the requester screen closes itself.
        player.closePluginMenu();
        unawaited(_programRequester(player, be, order, address));
        return;
      }
      if (!order.isEmpty) {
        // `WiFiEffectPacket.send(player.level(), pos)`: the keeper's link flashes.
        final world = be.world;
        if (world != null) {
          rt.bus.sendToTracking('create:packager_link_effect', world, be.pos, {
            'pos': be.pos,
          });
        }
      }
      unawaited(
        be.broadcastPackageRequest(RequestType.player, order, null, address),
      );
    });

    // `StockTickerInteractionHandler.interactWithLogisticsManager`: right-clicking a keeper (a
    // living entity riding a seat) opens the stock keeper when exactly one stock ticker is next
    // to it. The seat entity belongs to the contraptions module; the vehicle type key is enough.
    ctx.host.intercept(Events.playerInteractEntity, (server, e) async {
      if (e.action != EntityInteractionAction.interact) return e;
      if (e.player.isSpectator) return e;
      final target = e.player.getWorld().getEntityById(id: e.entityId);
      if (target == null) return e;
      final vehicle = target.getVehicle();
      if (vehicle == null) return e;
      // A seat is a plugin entity: its key is the registered one, `getType()` is null for it.
      final vehicleType = vehicle.getType();
      final vehicleKey =
          vehicle.getPluginTypeKey() ??
          (vehicleType == null
              ? null
              : 'minecraft:${vehicleType.wireName.replaceAll('-', '_')}');
      if (vehicleKey != _seatEntityKey) return e;
      if (target.asLiving() == null) return e;
      // `getStockTickerPosition`: the seat's block, the four horizontal sides and the two heights.
      final (px, py, pz) = target.getPosition();
      final base = (px.floor(), py.floor(), pz.floor());
      final world = e.player.getWorld();
      final found = <Pos>[];
      for (final side in Direction.planeHorizontal) {
        for (final y in [0, 1]) {
          final candidate = (base.$1 + side.stepX, base.$2 + y, base.$3 + side.stepZ);
          final state = world.getBlockState(pos: candidate.toBlockPos());
          if (state.blockName == 'create:stock_ticker') found.add(candidate);
        }
      }
      if (found.length != 1) return e;
      final pos = found.single;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(e.player),
        pos.toBlockPos(),
      );
      if (be == null) return e;
      final uuid = e.player.getId().asString;
      if (!be.behaviour.mayInteract(uuid)) {
        e.player.sendSystemMessage(
          text: TextComponent.translate(
            key: 'create.stock_keeper.locked',
            with_: const [],
          ),
          overlay: true,
        );
        return e.cancel();
      }
      final showLockOption =
          be.behaviour.mayAdministrate(uuid) &&
          rt.global.isLockable(be.behaviour.freqId);
      final opened = await StockKeeperMenus.openRequest(
        e.player,
        be,
        showLockOption: showLockOption,
        currentlyLocked: rt.global.isLocked(be.behaviour.freqId),
      );
      if (!opened) return e;
      await _sendStock(e.player, be);
      return e.cancel();
    });

    // `GhostItemSubmitPacket` of the stock keeper's category screen: the edited filter item.
    bus.onServerbound('create:submit_ghost_item', (player, fields) {
      final menu = player.currentPluginMenu;
      if (menu == null || menu.menuType != stockKeeperCategoryMenuType) return;
      final slot = fields['slot'] as int? ?? -1;
      final item = fields['item'];
      final stack = item is ItemStackData ? rt.wire.fromData(item) : LStack.empty;
      unawaited(StockKeeperMenus.submitGhost(player, slot, stack));
    });

    // `StockKeeperLockPacket`.
    bus.onServerbound('create:lock_stock_keeper', (player, fields) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos)) return;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      if (!be.behaviour.mayAdministrate(player.getId().asString)) return;
      final network = rt.global.logisticsNetworks[be.behaviour.freqId];
      if (network == null) return;
      network.locked = fields['lock'] == true;
      rt.global.markDirty();
    });

    // `StockKeeperCategoryEditPacket`.
    bus.onServerbound('create:configure_stock_keeper_categories', (
      player,
      fields,
    ) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos)) return;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      final schedule = fields['schedule'];
      if (schedule is! List) return;
      be.categories
        ..clear()
        ..addAll([
          for (final e in schedule)
            if (e is ItemStackData) rt.wire.fromData(e),
        ]);
      be.notifyUpdate();
    });

    // `StockKeeperCategoryRefundPacket`: the removed category's filter item is given back.
    bus.onServerbound('create:refund_stock_keeper_category', (player, fields) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos)) return;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      unawaited(_refundCategory(player, be, fields['filter']));
    });

    // `StockKeeperCategoryHidingPacket`: a per-player display preference of the stock keeper.
    bus.onServerbound('create:stock_keeper_hide_category', (player, fields) {
      final pos = fields['pos'] as Pos;
      if (!_mayConfigure(player, pos)) return;
      final be = rt.store.typed<StockTickerBlockEntity>(
        rt.playerWorldId(player),
        pos.toBlockPos(),
      );
      if (be == null) return;
      final uuid = player.getId().asString;
      final indices = fields['indices'];
      if (indices is! List || indices.isEmpty) {
        be.hiddenCategoriesByPlayer.remove(uuid);
        return;
      }
      be.hiddenCategoriesByPlayer[uuid] = [
        for (final i in indices)
          if (i is int) i,
      ];
      be.notifyUpdate();
    });
  }

  /// `RedstoneRequesterBlock.programRequester`: writes the order and the keeper's network onto
  /// the redstone requester (or table cloth) in the player's main hand.
  Future<void> _programRequester(
    Player player,
    StockTickerBlockEntity be,
    PackageOrderWithCrafts order,
    String address,
  ) async {
    final inventory = player.getInventory();
    try {
      final held = inventory.getItemInHand(hand: Hand.right);
      if (held == null) return;
      final stack = await Lg.i.read(held);
      if (stack.isEmpty) return;

      final isRequester = stack.key == 'create:redstone_requester';
      final isTableCloth = stack.key.endsWith('_table_cloth');
      if (!isRequester && !isTableCloth) return;

      final data = AutoRequestData(
        order,
        address,
        (be.pos.x, be.pos.y, be.pos.z),
        Lg.i.playerWorldId(player),
        false,
      );
      var out = stack.withComp(
        'create:auto_request_data',
        data.encode(Lg.i.wire),
      );
      if (isRequester) {
        out = LinkedItem.assignFrequency(out, be.behaviour.freqId);
      }

      final host = await Lg.i.write(out);
      if (host != null) {
        await inventory.setItemInHand(hand: Hand.right, item: host);
      }
    } finally {
      inventory.dispose();
    }
  }

  Future<void> _sendStock(Player player, StockCheckingBlockEntity be) async {
    final summary = await be.getRecentSummary();
    for (final (last, entries) in summary.divideForResponse()) {
      Lg.i.bus.sendClientbound('create:logistics_stock_response', player, {
        'lastPacket': last,
        'pos': be.pos,
        'items': [
          for (final e in entries)
            {'stack': Lg.i.wire.toData(e.stack), 'count': e.count},
        ],
      });
    }
  }

  Future<void> _refundCategory(
    Player player,
    StockTickerBlockEntity be,
    Object? filterField,
  ) async {
    if (filterField is! ItemStackData) return;
    final filter = Lg.i.wire.fromData(filterField);
    if (filter.isEmpty) return;
    // Only filter items are category filters.
    if (FilterMenuKind.of(filter.key) == null) return;
    await giveToPlayer(player, filter);
    be.notifyUpdate();
  }
}

/// The `PackageOrderWithCrafts` of a payload field map.
PackageOrderWithCrafts decodeOrder(Object? value) {
  if (value is! Map) return PackageOrderWithCrafts.empty();
  final ordered = value['orderedStacks'];
  final crafts = value['orderedCrafts'];
  return PackageOrderWithCrafts(
    PackageOrder([
      for (final e in (ordered is List ? ordered : const []))
        if (e is Map) BigStack(_stackOf(e['stack']), e['count'] as int? ?? 0),
    ]),
    [
      for (final e in (crafts is List ? crafts : const []))
        if (e is Map)
          CraftingEntry(
            PackageOrder([
              for (final s
                  in (e['pattern'] is List ? e['pattern'] as List : const []))
                if (s is Map)
                  BigStack(_stackOf(s['stack']), s['count'] as int? ?? 0),
            ]),
            e['count'] as int? ?? 1,
          ),
    ],
  );
}

LStack _stackOf(Object? value) =>
    value is ItemStackData ? Lg.i.wire.fromData(value) : LStack.empty;
