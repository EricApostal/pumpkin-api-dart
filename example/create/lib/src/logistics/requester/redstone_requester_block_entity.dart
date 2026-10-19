// `RedstoneRequesterBlockEntity`: sends the programmed order when it gets a redstone signal.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../host/runtime.dart';
import '../model/manager.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import '../stock/stock_ticker_block_entity.dart';
import 'auto_request_data.dart';

/// `RedstoneRequesterBlockEntity`.
class RedstoneRequesterBlockEntity extends StockCheckingBlockEntity {
  static const String type = 'create:redstone_requester';

  bool allowPartialRequests = false;
  PackageOrderWithCrafts encodedRequest = PackageOrderWithCrafts.empty();
  String encodedTargetAdress = '';
  bool lastRequestSucceeded = false;
  bool redstonePowered = false;

  final Map<String, dynamic> _state = {};

  RedstoneRequesterBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    super.readState(map);
    _state
      ..clear()
      ..addAll(map);
    redstonePowered = map['powered'] == true;
    lastRequestSucceeded = map['success'] == true;
    allowPartialRequests = map['allowPartial'] == true;
    encodedTargetAdress = map['address'] as String? ?? '';
    encodedRequest = map['request'] is Map
        ? PackageOrderWithCraftsMapper.fromMap(
            (map['request'] as Map).cast<String, dynamic>(),
          )
        : PackageOrderWithCrafts.empty();
  }

  @override
  Map<String, dynamic> stateToMap() => {
    ...super.stateToMap(),
    'powered': redstonePowered,
    'success': lastRequestSucceeded,
    'allowPartial': allowPartialRequests,
    'address': encodedTargetAdress,
    'request': encodedRequest.toMap(),
  };

  /// `onRedstonePowerChanged()`.
  void onRedstonePowerChanged() {
    unawaited(_powerChanged());
  }

  Future<void> _powerChanged() async {
    final w = world;
    if (w == null) return;
    final hasSignal = await w.hasRedstoneNeighborSignal(pos);
    if (redstonePowered == hasSignal) return;
    lastRequestSucceeded = false;
    if (hasSignal) await triggerRequest();
    redstonePowered = hasSignal;
    sendData();
  }

  /// `triggerRequest()`.
  Future<void> triggerRequest() async {
    if (encodedRequest.isEmpty) return;

    var anySucceeded = false;
    final summaryOfOrder = InventorySummary();
    for (final entry in encodedRequest.stacks) {
      summaryOfOrder.addBig(entry);
    }

    final summary = await getAccurateSummary();
    for (final entry in summaryOfOrder.getStacks()) {
      if (summary.countOf(entry.stack) >= entry.count) {
        anySucceeded = true;
        continue;
      }
      if (!allowPartialRequests) {
        _sendEffect(false);
        return;
      }
    }

    await broadcastPackageRequest(
      RequestType.redstone,
      encodedRequest,
      null,
      encodedTargetAdress,
    );
    _sendEffect(anySucceeded);
    lastRequestSucceeded = true;
  }

  void _sendEffect(bool success) {
    final w = world;
    if (w == null) return;
    Lg.i.bus.sendToTracking('create:redstone_requester_effect', w, pos, {
      'pos': pos,
      'success': success,
    });
  }

  /// The order of the requester, as `AutoRequestData` (used when it is picked up).
  AutoRequestData get requestData => AutoRequestData(
    encodedRequest,
    encodedTargetAdress,
    (0, 0, 0),
    worldId,
    true,
  );

  void setRequestData(AutoRequestData data) {
    encodedRequest = data.encodedRequest;
    encodedTargetAdress = data.encodedTargetAddress;
    sendData();
  }
}

/// `RedstoneRequesterBlockItem`: a requester item carries the programmed order and the network.
/// Reading and writing item components is left to the item's data component codecs; this keeps
/// the values for the block entity state.
final class RequesterProgram {
  final PackageOrderWithCrafts order;
  final String address;
  final String network;

  const RequesterProgram(this.order, this.address, this.network);
}

/// Helpers shared with the stock keeper screen (`RedstoneRequesterBlock.programRequester`).
abstract final class RedstoneRequesterBlock {
  /// The data written to the item: the order, the address and the keeper position.
  static AutoRequestData programRequester(
    PackageOrderWithCrafts order,
    String address,
    (int, int, int) keeperPos,
    String dimension,
  ) => AutoRequestData(order, address, keeperPos, dimension, false);

  static LStack withProgram(LStack stack, AutoRequestData data) => stack;
}
