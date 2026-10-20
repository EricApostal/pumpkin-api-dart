// `TableClothBlock` / `TableClothBlockEntity`: a decorative cloth that can be set up as a shop by
// programming it from a stock keeper.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/util.dart' hide pos;
import '../../content/advancement_ids.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../filter/filter_item_stack.dart';
import '../filter/filtering_behaviour.dart';
import '../host/lg_block_entity.dart';
import '../host/nbt_codecs.dart';
import '../host/nbt_util.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/manager.dart';
import '../model/stack.dart';
import '../requester/auto_request_data.dart';
import '../stock/stock_ticker_block_entity.dart';

/// The table cloth block keys (`AllBlocks.TABLE_CLOTHS` plus the three metal ones).
const List<String> tableClothKeys = [
  'white_table_cloth',
  'orange_table_cloth',
  'magenta_table_cloth',
  'light_blue_table_cloth',
  'yellow_table_cloth',
  'lime_table_cloth',
  'pink_table_cloth',
  'gray_table_cloth',
  'light_gray_table_cloth',
  'cyan_table_cloth',
  'purple_table_cloth',
  'blue_table_cloth',
  'brown_table_cloth',
  'green_table_cloth',
  'red_table_cloth',
  'black_table_cloth',
  'andesite_table_cloth',
  'brass_table_cloth',
  'copper_table_cloth',
];

/// `TableClothFilteringBehaviour`: the price tag. Unlike a plain filter it starts at an amount of
/// one, keeps that amount when the price item changes, and shows its count whenever a price is
/// set (`TableClothFilteringBehaviour.java:19-75`).
class TableClothFilteringBehaviour extends FilteringBehaviour {
  TableClothFilteringBehaviour(TableClothBlockEntity shop) : _shop = shop {
    count = 1;
    predicate = (stack) =>
        !FilterItemStack.of(stack).isFilterItem &&
        stack.key != 'create:shopping_list';
  }

  final TableClothBlockEntity _shop;

  @override
  bool get isCountVisible => filter.item.isNotEmpty;

  @override
  bool setFilter(LStack stack) {
    final before = count;
    final result = super.setFilter(stack);
    count = before;
    return result;
  }

  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {
    if (valueSettings == (row, value)) return;
    count = value < 1 ? 1 : value;
    upTo = row == 0;
    _shop.markDirty();
    _shop.sendData();
  }
}

/// `TableClothBlockEntity`.
class TableClothBlockEntity extends LgBlockEntity {
  static const String type = 'create:table_cloth';

  AutoRequestData requestData = AutoRequestData.empty();
  String? owner;
  Direction facing = Direction.south;
  List<LStack> manuallyAddedItems = [];
  late TableClothFilteringBehaviour priceTag;

  final Map<String, dynamic> _state = {};

  TableClothBlockEntity(super.worldId, super.pos) {
    priceTag = addBehaviour(TableClothFilteringBehaviour(this));
  }

  @override
  Map<String, dynamic> get state => _state;

  bool get isShop => !requestData.encodedRequest.isEmpty;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    final ownerData = map['OwnerUUID'];
    owner = ownerData is List && ownerData.length >= 4
        ? uuidFromInts([for (final i in ownerData) i as int])
        : map['owner'] as String?;
    facing = map['Facing'] is int
        ? Direction.from2DDataValue(map['Facing'] as int)
        : Direction.byName(map['facing'] as String? ?? 'south') ??
              Direction.south;
    requestData = map['RequestData'] is Map
        ? AutoRequestData.fromMap(
            (map['RequestData'] as Map).cast<String, dynamic>(),
          )
        : AutoRequestData.empty();
    manuallyAddedItems = [
      for (final s in (map['Items'] as List<dynamic>? ?? const []))
        if (s is String) LStackMapper.fromJson(s),
    ];
    final price = map['Filter'];
    if (price is String) priceTag.setFilter(LStackMapper.fromJson(price));
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'OwnerUUID': owner == null ? null : uuidToInts(owner!),
    'Facing': facing.data2d,
    'RequestData': requestData.toMap(),
    'Items': [for (final s in manuallyAddedItems) s.toJson()],
    'Filter': priceTag.filterItem.isEmpty ? null : priceTag.filterItem.toJson(),
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putList('Items', [
      for (final stack in manuallyAddedItems)
        if (stack.isNotEmpty) stackToNbt(stack, client: clientPacket),
    ]);
    tag.putInt('Facing', facing.data2d);
    tag.putCompound(
      'RequestData',
      autoRequestDataToNbt(requestData, client: clientPacket),
    );
    final ownerUuid = owner;
    if (ownerUuid != null) tag.putIntArray('OwnerUUID', uuidToInts(ownerUuid));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final items = tag.getList('Items');
    if (items != null) {
      // `readItemList` skips empty stacks.
      final parsed = <LStack>[];
      for (final entry in items) {
        if (entry is! NbtCompound) continue;
        final stack = stackFromNbt(entry);
        if (stack.isNotEmpty) parsed.add(stack);
      }
      manuallyAddedItems = parsed;
    }
    if (tag.containsKey('Facing')) {
      facing = Direction.from2DDataValue(tag.getInt('Facing') ?? 0);
    }
    final request = tag.getCompound('RequestData');
    if (request != null) requestData = autoRequestDataFromNbt(request);
    final ownerUuid = tag.getIntArray('OwnerUUID');
    if (ownerUuid != null && ownerUuid.length >= 4) {
      owner = uuidFromInts(ownerUuid);
    }
  }

  /// `use(player, ray)`.
  Future<bool> use(Player player, bool sneaking) async {
    if (isShop) return useShop(player);

    final held = await Lg.i.read(
      player.getInventory().getItemInHand(hand: Hand.right),
    );
    if (held.isEmpty) {
      if (manuallyAddedItems.isEmpty) return true;
      final last = manuallyAddedItems.removeLast();
      await giveToPlayer(player, last);
      if (manuallyAddedItems.isEmpty) {
        // `TableClothBlockEntity.use`: an empty cloth drops its block entity again, and the
        // clients have to remove the one they show (`create:remove_te`).
        final world = this.world;
        if (world != null) {
          final info = BlockStates.info(
            world.getBlockStateId(pos: pos),
          );
          if (info != null && info.key.startsWith('create:')) {
            await setBlockState(
              world,
              pos.toPos(),
              BState(info.key, info.properties).setFlag('entity', false),
            );
            Lg.i.bus.sendToTracking(
              'create:remove_te',
              world,
              pos,
              {'pos': pos.toPos()},
            );
            return true;
          }
        }
      }
      sendData();
      return true;
    }

    if (manuallyAddedItems.length >= 4) return true;
    manuallyAddedItems.add(held.withCount(1));
    await consumeOneInHand(player, Hand.right);
    sendData();
    return true;
  }

  /// `useShop(player)`: takes the price and broadcasts the shop's order to the keeper's network.
  Future<bool> useShop(Player player) async {
    final price = priceTag.filterItem;
    if (price.isEmpty) return true;

    final keeperPos = requestData.targetPos(pos.toPos());
    final world = this.world;
    if (world == null) return true;
    final ticker = store.typed<StockTickerBlockEntity>(
      worldId,
      keeperPos.toBlockPos(),
    );
    if (ticker == null || !ticker.isKeeperPresent) return true;

    // The keeper must have the requested items in stock (the recent summary is enough).
    final stock = await ticker.getRecentSummary();
    for (final entry in requestData.encodedRequest.stacks) {
      if (stock.countOf(entry.stack) >= entry.count) continue;
      return true;
    }

    // The order was already checked against the keeper's stock above.
    final inventory = playerInventory(player);
    var paid = 0;
    for (
      var slot = 0;
      slot < inventory.getSize() && paid < price.count;
      slot++
    ) {
      final host = inventory.getItem(slot: slot);
      if (host == null) continue;
      final stack = await Lg.i.read(host);
      if (stack.isEmpty || !stack.sameItemSameComponents(price)) continue;
      final take = price.count - paid < stack.count
          ? price.count - paid
          : stack.count;
      final removed = await inventory.removeItem(slot: slot);
      final rest = removed == null ? LStack.empty : await Lg.i.read(removed);
      if (rest.count > take) {
        final hostRest = await Lg.i.write(rest.withCount(rest.count - take));
        if (hostRest != null)
          await inventory.setItem(slot: slot, item: hostRest);
      }
      paid += take;
    }

    if (paid < price.count) {
      inventory.dispose();
      return true;
    }

    ticker.receivedPayments.insertStackedNow(price);
    await ticker.broadcastPackageRequest(
      RequestType.player,
      requestData.encodedRequest,
      null,
      requestData.encodedTargetAddress,
    );
    inventory.dispose();
    return true;
  }
}

/// `TableClothBlock`.
CreateBlock tableClothBlock(String key) => CreateBlock(
  key: 'create:$key',
  properties: [CreateProps.flag('entity')],
  hardness: 0.8,
  blastResistance: 0.8,
  soundType: 'wool',
  blockEntityType: TableClothBlockEntity.type,
  behavior: BlockBehavior(onUse: _onUse, onPlaced: _onPlaced),
);

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final worldId = e.targetWorld.getId();
  final info = BlockStates.info(e.targetWorld.getBlockStateId(pos: e.pos));
  if (info == null || !info.key.startsWith('create:')) return BlockUseResult.pass;

  final be = Lg.i.store.typed<TableClothBlockEntity>(worldId, e.pos);
  if (be == null) return BlockUseResult.pass;

  // `TableClothBlock.useItemOn`: the first use gives the cloth its block entity. The client
  // creates the block entity only when `entity` is true, so the items it shows need the update.
  if (info.properties['entity'] != 'true') {
    await setBlockState(
      e.targetWorld,
      e.pos.toPos(),
      BState(info.key, info.properties).setFlag('entity', true),
    );
  }

  await be.use(e.player, e.sneaking);
  return BlockUseResult.success;
}

Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
  // `TableClothBlock.setPlacedBy`: a cloth programmed at a stock keeper carries
  // `create:auto_request_data` and is placed as a shop.
  if (e.player == null) return;
  final player = Lg.i.player(e.player!.asString);
  if (player == null) return;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final data = await heldRequestData(player);
  if (data == null) return;

  final be = Lg.i.store.typed<TableClothBlockEntity>(world.getId(), e.pos);
  if (be == null) return;

  // `pLevel.setBlockAndUpdate(pPos, pState.setValue(HAS_BE, true))`: the cloth keeps its block
  // entity once it is a shop.
  final info = BlockStates.info(world.getBlockStateId(pos: e.pos));
  if (info == null || !info.key.startsWith('create:')) return;
  final state = BState(info.key, info.properties);
  if (state['entity'] != 'true') {
    await setBlockState(world, pos, state.setValue('entity', 'true'));
  }

  be.requestData = data.readFromItem(pos, world.getId());
  be.owner = player.getId().asString;
  be.facing = Direction.fromYRot(player.getYaw()).opposite;
  be.sendData();

  final advancements = Lg.i.advancements;
  if (advancements != null) {
    unawaited(advancements.award(player, AllAdvancements.tableClothShop));
  }
}

/// The `tablecloth` part.
final class TableClothPart extends LogisticsPart {
  @override
  String get name => 'tablecloth';

  @override
  void register(CreateRegistry registry) {
    for (final key in tableClothKeys) {
      registry.block(tableClothBlock(key));
    }
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: TableClothBlockEntity.type,
        validBlocks: [for (final key in tableClothKeys) 'create:$key'],
        create: TableClothBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    unawaited(Future<void>.value());
  }
}
