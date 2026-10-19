// `LogisticallyLinkedBehaviour` and `PackagerLinkBlockEntity`: a link that makes the packager it
// is attached to part of a logistics network. The same behaviour is used by the stock checking
// blocks (stock ticker, redstone requester), which join a network without global saved data.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../host/lg_block_entity.dart';
import '../host/lvl.dart';
import '../host/nbt_util.dart';
import '../host/runtime.dart';
import '../host/state_props.dart';
import '../model/inventory.dart';
import '../model/manager.dart';
import '../model/network.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import '../packager/packager_block_entity.dart';
import '../packager/repackager/repackager_block_entity.dart';

/// A link that can hand out an inventory summary and packaging requests
/// (`PackagerLinkBlockEntity`; a stock checking block has no packager).
abstract interface class LinkedHost {
  InventoryIdentifier? get inventoryIdentifier;

  Future<InventorySummary> fetchSummaryFromPackager(
    IdentifiedInventory? ignored,
  );

  Future<LinkRequest?> processRequest(
    LStack stack,
    int amount,
    String address,
    int linkIndex,
    MutableFlag finalLink,
    int orderId,
    PackageOrderWithCrafts? context,
    IdentifiedInventory? ignored,
  );
}

/// `LogisticallyLinkedBehaviour`: the network link of a stock link or stock checking block.
class LogisticallyLinkedBehaviour implements LogisticsLink {
  /// `LINK_ID_GENERATOR.getAndIncrement()`.
  final int linkId;

  final LgBlockEntity blockEntity;

  /// Whether the link is in the global network saved data (`global` in the Java class).
  final bool global;

  int redstonePower = 0;
  String freqId;

  bool addedGlobally = false;
  bool loadedGlobally = false;

  LogisticallyLinkedBehaviour(this.blockEntity, {required this.global})
    : linkId = Lg.i.links.newLinkId(),
      freqId = Lg.i.newUuid();

  LinkedHost? get _host =>
      blockEntity is LinkedHost ? blockEntity as LinkedHost : null;

  @override
  bool get isValid => !blockEntity.removed;

  @override
  InventoryIdentifier? get inventoryIdentifier => _host?.inventoryIdentifier;

  @override
  Future<InventorySummary> getSummary(IdentifiedInventory? ignored) async =>
      _host?.fetchSummaryFromPackager(ignored) ?? InventorySummary();

  @override
  Future<LinkRequest?> processRequest(
    LStack stack,
    int amount,
    String address,
    int linkIndex,
    MutableFlag finalLink,
    int orderId,
    PackageOrderWithCrafts? context,
    IdentifiedInventory? ignored,
  ) async => _host?.processRequest(
    stack,
    amount,
    address,
    linkIndex,
    finalLink,
    orderId,
    context,
    ignored,
  );

  @override
  void deductFromAccurateSummary(List<LStack> packageContents) {
    final summary = Lg.i.manager.accurateSummaries.getIfPresent(freqId);
    if (summary == null) return;
    for (final stack in packageContents) {
      if (stack.isEmpty) continue;
      summary.add(stack, -_min(summary.countOf(stack), stack.count));
    }
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// `initialize()`.
  void initialize() {
    if (global && !loadedGlobally) {
      loadedGlobally = true;
      Lg.i.global.linkLoaded(freqId, _globalPos);
      keepAlive();
    }
    if (global && !addedGlobally) {
      addedGlobally = true;
      blockEntity.markDirty();
      Lg.i.global.linkAdded(freqId, _globalPos, _placedBy);
    }
  }

  String? get _placedBy {
    final be = blockEntity;
    return be is PackagerLinkBlockEntity ? be.placedBy : null;
  }

  /// `lazyTick()`.
  void lazyTick() => keepAlive();

  /// `keepAlive(this)`.
  void keepAlive() {
    if (redstonePower == 15) return;
    Lg.i.links.keepAlive(linkId, this);
  }

  /// `unload()`.
  void onUnload() {
    if (loadedGlobally && global)
      Lg.i.global.linkInvalidated(freqId, _globalPos);
    Lg.i.links.remove(linkId, freqId);
  }

  /// `destroy()`.
  void onRemoved() {
    if (addedGlobally && global) Lg.i.global.linkRemoved(freqId, _globalPos);
    Lg.i.links.remove(linkId, freqId);
  }

  /// `redstonePowerChanged(power)`.
  void redstonePowerChanged(int power) {
    if (power == redstonePower) return;
    redstonePower = power;
    blockEntity.markDirty();
    if (power == 15) {
      Lg.i.links.remove(linkId, freqId);
    } else {
      keepAlive();
    }
  }

  GlobalPos get _globalPos => GlobalPos(
    blockEntity.worldId,
    blockEntity.pos.x,
    blockEntity.pos.y,
    blockEntity.pos.z,
  );

  bool mayInteract(String playerUuid) =>
      Lg.i.global.mayInteract(freqId, playerUuid);

  bool mayAdministrate(String playerUuid) =>
      Lg.i.global.mayAdministrate(freqId, playerUuid);

  /// `LogisticallyLinkedBehaviour.write`.
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag
      ..putIntArray('Freq', uuidToInts(freqId))
      ..putInt('Power', redstonePower)
      ..putBool('Added', addedGlobally);
  }

  /// `LogisticallyLinkedBehaviour.read`.
  void read(NbtCompound tag, {required bool clientPacket}) {
    final freq = tag.getIntArray('Freq');
    if (freq != null && freq.length >= 4) freqId = uuidFromInts(freq);
    redstonePower = tag.getInt('Power') ?? 0;
    addedGlobally = tag.getBool('Added') ?? false;
  }
}

/// `PackagerLinkBlockEntity`.
class PackagerLinkBlockEntity extends LgBlockEntity implements LinkedHost {
  static const String type = 'create:packager_link';

  late LogisticallyLinkedBehaviour behaviour;
  String? placedBy;

  final Map<String, dynamic> _state = {};

  PackagerLinkBlockEntity(super.worldId, super.pos) {
    behaviour = LogisticallyLinkedBehaviour(this, global: true);
  }

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    placedBy = map['PlacedBy'] as String?;
    behaviour.freqId = map['Freq'] as String? ?? behaviour.freqId;
    behaviour.redstonePower = map['Power'] as int? ?? 0;
    behaviour.addedGlobally = map['Added'] as bool? ?? false;
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'Freq': behaviour.freqId,
    'Power': behaviour.redstonePower,
    'Added': behaviour.addedGlobally,
    'PlacedBy': placedBy,
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    behaviour.write(tag, clientPacket: clientPacket);
    final placed = placedBy;
    if (placed != null) tag.putIntArray('PlacedBy', uuidToInts(placed));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    behaviour.read(tag, clientPacket: clientPacket);
    final placed = tag.getIntArray('PlacedBy');
    if (placed != null && placed.length >= 4) {
      placedBy = uuidFromInts(placed);
    }
  }

  /// This block entity's position as a [Pos].
  Pos get _pos => pos.toPos();

  @override
  void initialize() {
    super.initialize();
    behaviour.initialize();
    unawaited(refreshPower());
    packager?.recheckIfLinksPresent();
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

  void notifyUpdate() => sendData();

  /// The `facing`/`face` properties of the link.
  Direction get connectedDirection {
    final info = world == null ? null : Lvl(world!).info(_pos);
    return faceConnectedDirection(info?.properties ?? const {});
  }

  /// `PackagerLinkBlock.getPower(state, level, pos)`.
  Future<void> refreshPower() async {
    final w = world;
    if (w == null) return;
    var power = 0;
    for (final d in Direction.values) {
      if (d.opposite == connectedDirection) continue;
      final value = await w.redstonePower(
        _pos.relative(d).toBlockPos(),
        d.toHost(),
      );
      if (value > power) power = value;
    }
    behaviour.redstonePowerChanged(power);
  }

  /// The packager this link is attached to (`getPackager`).
  PackagerBlockEntity? get packager {
    if (behaviour.redstonePower == 15) return null;
    final source = _pos.relative(connectedDirection.opposite);
    final be = store.typed<PackagerBlockEntity>(worldId, source.toBlockPos());
    if (be == null || be is RepackagerBlockEntity) return null;
    return be;
  }

  @override
  InventoryIdentifier? get inventoryIdentifier =>
      packager?.identifiedInventory?.identifier;

  /// `fetchSummaryFromPackager(ignoredHandler)`.
  @override
  Future<InventorySummary> fetchSummaryFromPackager(
    IdentifiedInventory? ignored,
  ) async {
    final packager = this.packager;
    if (packager == null) return InventorySummary();
    if (packager.isTargetingSameInventory(ignored)) return InventorySummary();
    return packager.getAvailableItems();
  }

  /// `processRequest(...)`.
  @override
  Future<LinkRequest?> processRequest(
    LStack stack,
    int amount,
    String address,
    int linkIndex,
    MutableFlag finalLink,
    int orderId,
    PackageOrderWithCrafts? context,
    IdentifiedInventory? ignored,
  ) async {
    final packager = this.packager;
    if (packager == null) return null;
    if (packager.isTargetingSameInventory(ignored)) return null;

    final summary = await packager.getAvailableItems();
    final available = summary.countOf(stack);
    if (available == 0) return null;
    final toWithdraw = amount < available ? amount : available;
    return LinkRequest(
      packager,
      PackagingRequest.create(
        stack,
        toWithdraw,
        address,
        linkIndex,
        finalLink,
        0,
        orderId,
        context,
      ),
    );
  }
}
