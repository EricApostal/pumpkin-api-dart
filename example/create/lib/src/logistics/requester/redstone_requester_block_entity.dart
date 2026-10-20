// `RedstoneRequesterBlockEntity`: sends the programmed order when it gets a redstone signal.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../host/nbt_codecs.dart';
import '../host/runtime.dart';
import '../model/manager.dart';
import '../model/orders.dart';
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
    redstonePowered = map['Powered'] == true;
    lastRequestSucceeded = map['Success'] == true;
    allowPartialRequests = map['AllowPartial'] == true;
    encodedTargetAdress = map['EncodedAddress'] as String? ?? '';
    encodedRequest = map['EncodedRequest'] is Map
        ? PackageOrderWithCraftsMapper.fromMap(
            (map['EncodedRequest'] as Map).cast<String, dynamic>(),
          )
        : PackageOrderWithCrafts.empty();
  }

  @override
  Map<String, dynamic> stateToMap() => {
    ...super.stateToMap(),
    'Powered': redstonePowered,
    'Success': lastRequestSucceeded,
    'AllowPartial': allowPartialRequests,
    'EncodedAddress': encodedTargetAdress,
    'EncodedRequest': encodedRequest.toMap(),
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag
      ..putBool('Powered', redstonePowered)
      ..putBool('Success', lastRequestSucceeded)
      ..putBool('AllowPartial', allowPartialRequests)
      ..putString('EncodedAddress', encodedTargetAdress)
      ..putCompound(
        'EncodedRequest',
        orderWithCraftsToNbt(encodedRequest, client: clientPacket),
      );
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('Powered')) {
      redstonePowered = tag.getBool('Powered') ?? false;
    }
    if (tag.containsKey('Success')) {
      lastRequestSucceeded = tag.getBool('Success') ?? false;
    }
    if (tag.containsKey('AllowPartial')) {
      allowPartialRequests = tag.getBool('AllowPartial') ?? false;
    }
    if (tag.containsKey('EncodedAddress')) {
      encodedTargetAdress = tag.getString('EncodedAddress') ?? '';
    }
    final request = tag.getCompound('EncodedRequest');
    if (request != null) encodedRequest = orderWithCraftsFromNbt(request);
  }

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

  /// `setRequestData`: the order a requester placed from a programmed item keeps
  /// (`RedstoneRequesterBlock.setPlacedBy`).
  void setRequestData(AutoRequestData data) {
    encodedRequest = data.encodedRequest;
    encodedTargetAdress = data.encodedTargetAddress;
    sendData();
  }
}
