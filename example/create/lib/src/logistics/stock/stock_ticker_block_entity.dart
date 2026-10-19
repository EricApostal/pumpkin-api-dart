// `StockCheckingBlockEntity` and `StockTickerBlockEntity`: the blocks that query a logistics
// network's stock and broadcast package orders.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../filter/filter_item_stack.dart';
import '../host/lg_block_entity.dart';
import '../host/nbt_codecs.dart';
import '../host/nbt_util.dart';
import '../host/runtime.dart';
import '../link/packager_link_block_entity.dart';
import '../model/inventory.dart';
import '../model/manager.dart';
import '../model/orders.dart';
import '../model/stack.dart';

/// `StockCheckingBlockEntity`: a block that is linked to a network without joining the global
/// saved data (stock ticker, redstone requester).
abstract class StockCheckingBlockEntity extends LgBlockEntity {
  late LogisticallyLinkedBehaviour behaviour;

  StockCheckingBlockEntity(super.worldId, super.pos) {
    behaviour = LogisticallyLinkedBehaviour(this, global: false);
  }

  @override
  void readState(Map<String, dynamic> map) {
    behaviour.freqId = map['Freq'] as String? ?? behaviour.freqId;
    behaviour.redstonePower = map['Power'] as int? ?? 0;
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'Freq': behaviour.freqId,
    'Power': behaviour.redstonePower,
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    behaviour.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    behaviour.read(tag, clientPacket: clientPacket);
  }

  @override
  void initialize() {
    super.initialize();
    behaviour.initialize();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    behaviour.lazyTick();
  }

  @override
  void onUnload() {
    behaviour.onUnload();
    super.onUnload();
  }

  @override
  void onRemoved() {
    behaviour.onRemoved();
    super.onRemoved();
  }

  /// `getRecentSummary()`.
  Future<InventorySummary> getRecentSummary() =>
      Lg.i.manager.getSummaryOfNetwork(behaviour.freqId, accurate: false);

  /// `getAccurateSummary()`.
  Future<InventorySummary> getAccurateSummary() =>
      Lg.i.manager.getSummaryOfNetwork(behaviour.freqId, accurate: true);

  /// `broadcastPackageRequest(type, order, ignoredHandler, address)`.
  Future<bool> broadcastPackageRequest(
    RequestType type,
    PackageOrderWithCrafts order,
    IdentifiedInventory? ignored,
    String address,
  ) => Lg.i.manager.broadcastPackageRequest(
    behaviour.freqId,
    type,
    order,
    ignored,
    address,
  );
}

/// `StockTickerBlockEntity`: the stock keeper's terminal. It also stores the payments of shop
/// trades.
class StockTickerBlockEntity extends StockCheckingBlockEntity {
  static const String type = 'create:stock_ticker';

  final MemoryInv receivedPayments = MemoryInv(27, limit: 64);
  final List<LStack> categories = [];

  /// `hiddenCategoriesByPlayer`: the category indices a player hid in the stock keeper.
  final Map<String, List<int>> hiddenCategoriesByPlayer = {};

  String previouslyUsedAddress = '';
  int activeLinks = 0;

  final Map<String, dynamic> _state = {};

  StockTickerBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    super.readState(map);
    _state
      ..clear()
      ..addAll(map);
    previouslyUsedAddress = map['PreviousAddress'] as String? ?? '';
    categories
      ..clear()
      ..addAll([
        for (final c in (map['Categories'] as List<dynamic>? ?? const []))
          if (c is String) _stack(c),
      ]);
    final payments = map['ReceivedPayments'] as List<dynamic>? ?? const [];
    for (var i = 0; i < receivedPayments.slots && i < payments.length; i++) {
      receivedPayments.stacks[i] = payments[i] is String
          ? _stack(payments[i] as String)
          : LStack.empty;
    }
    activeLinks = map['ActiveLinks'] as int? ?? 0;
    hiddenCategoriesByPlayer.clear();
    for (final entry
        in (map['HiddenCategories'] as List<dynamic>? ?? const [])) {
      if (entry is! Map) continue;
      final id = entry['Id'];
      final indices = entry['Indices'];
      if (id is! String || indices is! List) continue;
      hiddenCategoriesByPlayer[id] = [
        for (final i in indices)
          if (i is int) i,
      ];
    }
  }

  static LStack _stack(String json) {
    try {
      return LStackMapper.fromJson(json);
    } on Object {
      return LStack.empty;
    }
  }

  @override
  Map<String, dynamic> stateToMap() => {
    ...super.stateToMap(),
    'PreviousAddress': previouslyUsedAddress,
    'Categories': [for (final c in categories) c.toJson()],
    'ReceivedPayments': [
      for (final s in receivedPayments.stacks) s.isEmpty ? null : s.toJson(),
    ],
    'ActiveLinks': activeLinks,
    'HiddenCategories': [
      for (final e in hiddenCategoriesByPlayer.entries)
        {'Id': e.key, 'Indices': e.value},
    ],
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putString('PreviousAddress', previouslyUsedAddress);
    tag.putCompound(
      'ReceivedPayments',
      itemHandlerToNbt(receivedPayments, client: clientPacket),
    );
    tag.putList('Categories', [
      for (final stack in categories) stackToNbt(stack, client: clientPacket),
    ]);
    tag.putList('HiddenCategories', [
      for (final entry in hiddenCategoriesByPlayer.entries)
        NbtCompound()
          ..putIntArray('Id', uuidToInts(entry.key))
          ..putIntArray('Indices', entry.value),
    ]);
    // Java only sends the link count to the client.
    if (clientPacket) tag.putInt('ActiveLinks', activeLinks);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('PreviousAddress')) {
      previouslyUsedAddress = tag.getString('PreviousAddress') ?? '';
    }
    final payments = tag.getCompound('ReceivedPayments');
    if (payments != null) itemHandlerFromNbt(payments, receivedPayments);
    final categoryList = tag.getList('Categories');
    if (categoryList != null) {
      categories
        ..clear()
        ..addAll([
          for (final entry in categoryList)
            if (entry is NbtCompound) stackFromNbt(entry),
        ]);
      // `categories.removeIf(...)`: only filter items are valid category filters.
      categories.removeWhere(
        (stack) =>
            stack.isNotEmpty &&
            !const {
              FilterItemKeys.list,
              FilterItemKeys.attribute,
              FilterItemKeys.package,
            }.contains(stack.key),
      );
    }
    hiddenCategoriesByPlayer.clear();
    for (final entry in tag.getList('HiddenCategories') ?? const <Object>[]) {
      if (entry is! NbtCompound) continue;
      final id = entry.getIntArray('Id');
      if (id == null || id.length < 4) continue;
      hiddenCategoriesByPlayer[uuidFromInts(id)] =
          entry.getIntArray('Indices') ?? const [];
    }
    if (clientPacket) activeLinks = tag.getInt('ActiveLinks') ?? activeLinks;
  }

  @override
  Future<InventorySummary> getRecentSummary() async {
    final recent = await super.getRecentSummary();
    if (activeLinks != recent.contributingLinks && !removed) {
      activeLinks = recent.contributingLinks;
      sendData();
    }
    return recent;
  }

  @override
  Future<bool> broadcastPackageRequest(
    RequestType type,
    PackageOrderWithCrafts order,
    IdentifiedInventory? ignored,
    String address,
  ) async {
    final result = await super.broadcastPackageRequest(
      type,
      order,
      ignored,
      address,
    );
    previouslyUsedAddress = address;
    notifyUpdate();
    return result;
  }

  void notifyUpdate() => sendData();

  /// `isKeeperPresent()`: a heater or a seat next to the ticker. The seat entity belongs to the
  /// contraptions module, which is not a dependency here; a heater is checked.
  bool get isKeeperPresent {
    for (final yOffset in [0, 1]) {
      for (final side in Direction.planeHorizontal) {
        final seatPos = pos.toPos().belowBy(yOffset).relative(side);
        if (yOffset == 0) {
          final info = world == null ? null : LvlInfo.of(world!, seatPos);
          if (info == 'create:heater') return true;
        }
      }
    }
    return false;
  }

  /// `receiveStockPacket`: the client side snapshot is not used on the server.
  void receiveStockPacket(List<BigStack> stacks, bool endOfTransmission) {}

  /// The payments the shop trade left in the ticker.
  void clearPayments() {
    receivedPayments.clear();
    markDirty();
  }

  @override
  void onRemoved() {
    final w = world;
    if (w != null) unawaited(_dropStored(w));
    super.onRemoved();
  }

  Future<void> _dropStored(World w) async {
    for (final stack in receivedPayments.nonEmpty()) {
      final host = await Lg.i.write(stack);
      if (host != null) await w.dropItem(pos.toPos().center, host);
    }
    for (final stack in categories) {
      final host = await Lg.i.write(stack);
      if (host != null) await w.dropItem(pos.toPos().center, host);
    }
    receivedPayments.clear();
    categories.clear();
  }
}

/// A tiny block key lookup (the Lvl helper is not imported to keep this file light).
abstract final class LvlInfo {
  static String? of(World world, Pos pos) {
    final id = world.getBlockStateId(pos: pos.toBlockPos());
    return BlockStates.info(id)?.key;
  }
}
