// `FactoryPanelBehaviour`: one gauge of a factory panel, its connections to other gauges and its
// restock/request loop.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/panel_support.dart';
import '../../api/util.dart' hide pos;
import '../filter/filter_item_stack.dart';
import '../filter/filtering_behaviour.dart';
import '../host/lvl.dart';
import '../host/nbt_codecs.dart';
import '../host/nbt_util.dart';
import '../host/runtime.dart';
import '../model/manager.dart';
import '../model/network.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import 'factory_panel_block_entity.dart';

/// `FactoryPanelBlock.PanelSlot`: which quarter of the panel a gauge occupies.
enum PanelSlot {
  topLeft('top_left', 1, 1),
  topRight('top_right', 0, 1),
  bottomLeft('bottom_left', 1, 0),
  bottomRight('bottom_right', 0, 0);

  const PanelSlot(this.serializedName, this.xOffset, this.yOffset);

  final String serializedName;
  final int xOffset;
  final int yOffset;

  static PanelSlot? byName(String name) {
    for (final s in values) {
      if (s.serializedName == name) return s;
    }
    return null;
  }
}

/// `FactoryPanelPosition`.
final class FactoryPanelPosition {
  final Pos pos;
  final PanelSlot slot;

  const FactoryPanelPosition(this.pos, this.slot);

  /// The packet form: the position as a packed `BlockPos` and the slot ordinal (what the
  /// clientbound encoder and the state JSON both expect). `FactoryPanelPosition.STREAM_CODEC`.
  Map<String, dynamic> toMap() => {
    'pos': [pos.$1, pos.$2, pos.$3],
    'slot': slot.index,
  };

  /// Reads the packet form (a `BlockPos` record and the slot ordinal) and the older JSON form
  /// (a list and the slot name).
  static FactoryPanelPosition? fromMap(Object? value) {
    if (value is! Map) return null;
    final p = value['pos'];
    final (int, int, int)? position = switch (p) {
      (final int x, final int y, final int z) => (x, y, z),
      final List list when list.length == 3 => (
        list[0] as int,
        list[1] as int,
        list[2] as int,
      ),
      _ => null,
    };
    final slot = switch (value['slot']) {
      final int ordinal
          when ordinal >= 0 && ordinal < PanelSlot.values.length =>
        PanelSlot.values[ordinal],
      final String name => PanelSlot.byName(name),
      _ => null,
    };
    if (position == null || slot == null) return null;
    return FactoryPanelPosition(position, slot);
  }

  @override
  bool operator ==(Object other) =>
      other is FactoryPanelPosition && other.pos == pos && other.slot == slot;

  @override
  int get hashCode => Object.hash(pos, slot);
}

/// `FactoryPanelConnection`: an input gauge and how many items it contributes.
final class FactoryPanelConnection {
  FactoryPanelPosition from;
  int amount;
  int arrowBendMode;
  bool success = true;

  FactoryPanelConnection(this.from, this.amount, [this.arrowBendMode = -1]);

  Map<String, dynamic> toMap() => {
    'position': from.toMap(),
    'amount': amount,
    'arrow_bending': arrowBendMode,
  };

  static FactoryPanelConnection? fromMap(Object? value) {
    if (value is! Map) return null;
    final from = FactoryPanelPosition.fromMap(value['position']);
    if (from == null) return null;
    return FactoryPanelConnection(
      from,
      value['amount'] as int? ?? 0,
      value['arrow_bending'] as int? ?? -1,
    );
  }
}

/// `FactoryPanelBehaviour`.
class FactoryPanelBehaviour extends FilteringBehaviour
    implements FactoryPanelHandle {
  /// `BlockEntityBehaviour.blockEntity`: not final, [moveTo] rebinds it to the target block.
  FactoryPanelBlockEntity panelBE;
  PanelSlot slot;

  bool active = false;
  String recipeAddress = '';
  int recipeOutput = 1;
  int promiseClearingInterval = -1;
  String network;

  bool satisfied = false;
  bool promisedSatisfied = false;
  bool waitingForNetwork = false;
  bool redstonePowered = false;
  bool forceClearPromises = false;

  final Map<FactoryPanelPosition, FactoryPanelConnection> targetedBy = {};
  final Map<Pos, FactoryPanelConnection> targetedByLinks = {};
  final Set<FactoryPanelPosition> targeting = {};
  List<LStack> activeCraftingArrangement = [];

  late RequestPromiseQueue restockerPromises;

  int _timer = 0;
  int _lastReportedUnloadedLinks = 0;
  int _lastReportedLevelInStorage = 0;
  int _lastReportedPromises = 0;

  FactoryPanelBehaviour(this.panelBE, this.slot) : network = Lg.i.newUuid() {
    restockerPromises = RequestPromiseQueue(() => panelBE.markDirty());
    count = 0;
  }

  /// `setNetwork`.
  void setNetwork(String id) => network = id;

  /// `FactoryPanelBehaviour.at(world, position)`.
  static FactoryPanelBehaviour? at(
    String worldId,
    FactoryPanelPosition position,
  ) {
    final be = Lg.i.store.typed<FactoryPanelBlockEntity>(
      worldId,
      position.pos.toBlockPos(),
    );
    final behaviour = be?.panels[position.slot];
    if (behaviour == null || !behaviour.active) return null;
    return behaviour;
  }

  static FactoryPanelBehaviour? atConnection(
    String worldId,
    FactoryPanelConnection connection,
  ) => at(worldId, connection.from);

  /// `FactoryPanelBehaviour.linkAt(world, position)`: the `PanelSupportBehaviour` of a redstone
  /// link or display link (owned by the redstone module), `null` for a gauge or a plain block.
  static PanelSupportBehaviour? linkAt(
    String worldId,
    FactoryPanelPosition position,
  ) {
    final be = Lg.i.store.at(worldId, position.pos.toBlockPos());
    return be?.getBehaviour<PanelSupportBehaviour>();
  }

  static PanelSupportBehaviour? linkAtConnection(
    String worldId,
    FactoryPanelConnection connection,
  ) => linkAt(worldId, connection.from);

  /// The `api/panel_support.dart` position of a panel (`FactoryPanelPos`).
  static FactoryPanelPos apiPosition(FactoryPanelPosition position) =>
      FactoryPanelPos(
        position.pos,
        PanelSlotId.byName(position.slot.serializedName) ??
            PanelSlotId.bottomLeft,
      );

  FactoryPanelPosition getPanelPosition() =>
      FactoryPanelPosition(panelBE.pos.toPos(), slot);

  @override
  bool get isActive => active;

  @override
  int get netId => 2 + slot.index;

  @override
  int get levelInStorage => getLevelInStorage;

  @override
  String get filterName => filter.item.isEmpty ? '' : filter.item.key;

  @override
  int get demand => count * (upTo ? 1 : maxSize);

  @override
  int get promised => getPromised;

  @override
  int get ingredientStatusColor =>
      count == 0 || isMissingAddress || redstonePowered
      ? 0x888898
      : waitingForNetwork
      ? 0x5B3B3B
      : satisfied
      ? 0x9EFF7F
      : promisedSatisfied
      ? 0x22AFAF
      : 0x3D6EBD;

  /// `FilteringBehaviour.getMaxStackSize()`.
  int get maxSize => filter.maxStackSize;

  @override
  void removeLink(Pos linkPos) {
    targetedByLinks.remove(linkPos);
    panelBE.notifyUpdate();
  }

  @override
  bool canShortInteract(String itemKey) => true;

  bool get isMissingAddress =>
      (targetedBy.isNotEmpty || panelBE.restocker) &&
      count != 0 &&
      recipeAddress.trim().isEmpty;

  void enable() {
    active = true;
    panelBE.notifyUpdate();
  }

  void disable() {
    disconnectAll();
    active = false;
    targetedBy.clear();
    targeting.clear();
    count = 0;
    satisfied = false;
    promisedSatisfied = false;
    recipeAddress = '';
    recipeOutput = 1;
    filter = FilterItemStack.empty;
    panelBE.notifyUpdate();
  }

  /// `setFilter(stack)`: filter items are not accepted.
  @override
  bool setFilter(LStack stack) {
    if (stack.isNotEmpty && FilterItemStack.of(stack).isFilterItem)
      return false;
    filter = FilterItemStack.of(stack, wire: Lg.i.wire);
    panelBE.markDirty();
    panelBE.sendData();
    return true;
  }

  /// `setValueSettings(player, settings, ctrlDown)`.
  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {
    final settings = valueSettings;
    if (settings.$1 == row && settings.$2 == value) return;
    count = max(0, value);
    upTo = row == 0;
    panelBE.redraw = true;
    panelBE.markDirty();
    panelBE.sendData();
    resetTimerSlightly();
    notifyRedstoneOutputs();
  }

  /// `moveTo(newPos, player)`: moves this gauge to another slot of a gauge block (the
  /// `relocate` flag of `FactoryPanelConnectionPacket`). The block at the target must be air or a
  /// gauge with the same state, and all connections must stay within 24 blocks.
  Future<void> moveTo(FactoryPanelPosition newPos, Player player) async {
    final world = panelBE.world;
    if (world == null) return;
    final lvl = Lvl(world);
    if (FactoryPanelBehaviour.at(panelBE.worldId, newPos) != null) return;

    final existingInfo = lvl.info(newPos.pos);
    final existingKey = existingInfo?.key ?? 'minecraft:air';
    final isAddedToOtherGauge = existingKey == 'create:factory_gauge';
    final isAir = existingKey == 'minecraft:air';
    if (!isAir && !isAddedToOtherGauge) return;

    final ownState = lvl.stateId(panelBE.pos.toPos());
    if (isAddedToOtherGauge) {
      if (lvl.stateId(newPos.pos) != ownState) return;
    } else {
      await lvl.setState(newPos.pos, ownState, neighbors: true);
    }

    for (final pos in targetedByLinks.keys) {
      if (!pos.closerThan(newPos.pos, 24)) return;
    }
    for (final position in targetedBy.keys) {
      if (!position.pos.closerThan(newPos.pos, 24)) return;
    }
    for (final position in targeting) {
      if (!position.pos.closerThan(newPos.pos, 24)) return;
    }

    // Disconnect the links; they are reconnected below.
    for (final pos in targetedByLinks.keys.toList()) {
      linkAt(
        panelBE.worldId,
        FactoryPanelPosition(pos, slot),
      )?.disconnect(apiPosition(getPanelPosition()));
    }

    final oldBE = panelBE;
    final oldPos = getPanelPosition();
    moveToSlot(newPos.slot);

    // Add to the new block entity. `addBehaviour` sets `owner`; rebinding [panelBE] makes the
    // moved gauge tick and render on its new block, like Java's `attachBehaviourLate`.
    final newBE = Lg.i.store.typed<FactoryPanelBlockEntity>(
      panelBE.worldId,
      newPos.pos.toBlockPos(),
    );
    if (newBE != null) {
      newBE.addBehaviour(this);
      newBE.panels[slot] = this;
      panelBE = newBE;
      newBE.redraw = true;
      newBE.lastShape = null;
      newBE.world?.invalidateShape(newPos.pos.toBlockPos());
      newBE.notifyUpdate();
    }

    // Leave a fresh, inactive gauge in the old slot.
    final replacement = FactoryPanelBehaviour(oldBE, oldPos.slot);
    oldBE.addBehaviour(replacement);
    oldBE.panels[oldPos.slot] = replacement;
    oldBE.redraw = true;
    oldBE.lastShape = null;
    oldBE.world?.invalidateShape(oldPos.pos.toBlockPos());
    oldBE.notifyUpdate();

    // Rewire the connections.
    for (final position in targeting.toList()) {
      final source = FactoryPanelBehaviour.at(panelBE.worldId, position);
      if (source == null) continue;
      final connection = source.targetedBy.remove(oldPos);
      if (connection == null) continue;
      connection.from = newPos;
      source.targetedBy[newPos] = connection;
      source.panelBE.sendData();
    }
    for (final position in targetedBy.keys.toList()) {
      final source = FactoryPanelBehaviour.at(panelBE.worldId, position);
      if (source == null) continue;
      source.targeting.remove(oldPos);
      source.targeting.add(newPos);
    }
    for (final pos in targetedByLinks.keys.toList()) {
      linkAt(
        panelBE.worldId,
        FactoryPanelPosition(pos, slot),
      )?.connect(apiPosition(newPos));
    }

    player.send(Messages.component('factory_panel.relocated'));
  }

  void moveToSlot(PanelSlot newSlot) {
    slot = newSlot;
  }

  @override
  void initialize() {
    if (owner != panelBE) return;
    super.initialize();
    notifyRedstoneOutputs();
  }

  @override
  void tick() {
    if (owner != panelBE) return;
    super.tick();
    tickStorageMonitor();
    tickRequests();
  }

  @override
  void lazyTick() {
    if (owner != panelBE) return;
    super.lazyTick();
    checkForRedstoneInput();
  }

  // Java stores each gauge in its own compound named after the slot; the filtering behaviour's
  // flat keys therefore do not collide.
  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    if (!active) return;
    final panelTag = NbtCompound();
    super.write(panelTag, clientPacket: clientPacket);
    panelTag
      ..putInt('Timer', _timer)
      ..putInt('LastLevel', _lastReportedLevelInStorage)
      ..putInt('LastPromised', _lastReportedPromises)
      ..putInt('LastUnloadedLinks', _lastReportedUnloadedLinks)
      ..putBool('Satisfied', satisfied)
      ..putBool('PromisedSatisfied', promisedSatisfied)
      ..putBool('Waiting', waitingForNetwork)
      ..putBool('RedstonePowered', redstonePowered)
      ..putList('Targeting', [
        for (final position in targeting) _positionToNbt(position),
      ])
      ..putList('TargetedBy', [
        for (final connection in targetedBy.values)
          _connectionToNbt(connection),
      ])
      ..putList('TargetedByLinks', [
        for (final connection in targetedByLinks.values)
          _connectionToNbt(connection),
      ])
      ..putString('RecipeAddress', recipeAddress)
      ..putInt('RecipeOutput', recipeOutput)
      ..putInt('PromiseClearingInterval', promiseClearingInterval)
      ..putIntArray('Freq', uuidToInts(network))
      ..putList('Craft', [
        for (final stack in activeCraftingArrangement)
          stackToNbt(stack, client: clientPacket),
      ]);
    if (panelBE.restocker && !clientPacket) {
      panelTag.putCompound(
        'Promises',
        requestPromiseQueueToNbt(restockerPromises, client: false),
      );
    }
    tag.putCompound(slot.serializedName, panelTag);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final panelTag = tag.getCompound(slot.serializedName);
    // An absent compound keeps the state loaded from the private JSON (old saves).
    if (panelTag == null) return;
    active = true;
    // `FactoryPanelBehaviour.read`: the panel reads its own filter fields and never calls
    // `FilteringBehaviour.read`, so an amount of 0 is not migrated to the stack size (Java keeps
    // it, `FactoryPanelBehaviour.java:872-874`).
    filter = FilterItemStack.of(
      stackFromNbt(panelTag.getCompound('Filter')),
      wire: Lg.loaded ? Lg.i.wire : null,
    );
    count = panelTag.getInt('FilterAmount') ?? 0;
    upTo = panelTag.getBool('UpTo') ?? false;
    _timer = panelTag.getInt('Timer') ?? 0;
    _lastReportedLevelInStorage = panelTag.getInt('LastLevel') ?? 0;
    _lastReportedPromises = panelTag.getInt('LastPromised') ?? 0;
    _lastReportedUnloadedLinks = panelTag.getInt('LastUnloadedLinks') ?? 0;
    satisfied = panelTag.getBool('Satisfied') ?? false;
    promisedSatisfied = panelTag.getBool('PromisedSatisfied') ?? false;
    waitingForNetwork = panelTag.getBool('Waiting') ?? false;
    redstonePowered = panelTag.getBool('RedstonePowered') ?? false;
    promiseClearingInterval = panelTag.getInt('PromiseClearingInterval') ?? 0;
    final freq = panelTag.getIntArray('Freq');
    if (freq != null && freq.length >= 4) network = uuidFromInts(freq);

    targeting.clear();
    for (final entry in panelTag.getList('Targeting') ?? const <Object>[]) {
      if (entry is! NbtCompound) continue;
      final position = _positionFromNbt(entry);
      if (position != null) targeting.add(position);
    }
    targetedBy.clear();
    for (final entry in panelTag.getList('TargetedBy') ?? const <Object>[]) {
      if (entry is! NbtCompound) continue;
      final connection = _connectionFromNbt(entry);
      if (connection != null) targetedBy[connection.from] = connection;
    }
    targetedByLinks.clear();
    for (final entry
        in panelTag.getList('TargetedByLinks') ?? const <Object>[]) {
      if (entry is! NbtCompound) continue;
      final connection = _connectionFromNbt(entry);
      if (connection != null) targetedByLinks[connection.from.pos] = connection;
    }
    activeCraftingArrangement = [
      for (final entry in panelTag.getList('Craft') ?? const <Object>[])
        if (entry is NbtCompound) stackFromNbt(entry),
    ];
    recipeAddress = panelTag.getString('RecipeAddress') ?? '';
    recipeOutput = panelTag.getInt('RecipeOutput') ?? 0;

    if (panelBE.restocker && !clientPacket) {
      restockerPromises = requestPromiseQueueFromNbt(
        panelTag.getCompound('Promises'),
        () => panelBE.markDirty(),
      );
    }
  }

  /// `checkForRedstoneInput()`.
  void checkForRedstoneInput() {
    if (!active) return;

    var shouldPower = false;
    for (final connection in targetedByLinks.values) {
      final world = panelBE.world;
      if (world == null ||
          !world.isLoaded(pos: connection.from.pos.toBlockPos()))
        return;
      final link = linkAt(panelBE.worldId, connection.from);
      if (link == null) return;
      shouldPower |= link.shouldPanelBePowered;
    }

    if (shouldPower == redstonePowered) return;
    redstonePowered = shouldPower;
    panelBE.notifyUpdate();
    _timer = 1;
  }

  void notifyRedstoneOutputs() {
    for (final connection in targetedByLinks.values) {
      final world = panelBE.world;
      if (world == null ||
          !world.isLoaded(pos: connection.from.pos.toBlockPos()))
        return;
      final link = linkAt(panelBE.worldId, connection.from);
      if (link == null || link.isOutput) return;
      link.notifyLink();
    }
  }

  /// `tickStorageMonitor()`.
  void tickStorageMonitor() {
    final item = filter.item;
    final unloadedLinkCount = getUnloadedLinks;
    if (!panelBE.restocker &&
        unloadedLinkCount == 0 &&
        _lastReportedUnloadedLinks != 0) {
      Lg.i.manager.summaries.invalidate(network);
    }

    final inStorage = getLevelInStorage;
    final promised = getPromised;
    final demand = count * (upTo ? 1 : max(1, filter.maxStackSize));
    final shouldSatisfy = item.isEmpty || inStorage >= demand;
    final shouldPromiseSatisfy = item.isEmpty || inStorage + promised >= demand;
    final shouldWait = unloadedLinkCount > 0;

    if (_lastReportedLevelInStorage == inStorage &&
        _lastReportedPromises == promised &&
        _lastReportedUnloadedLinks == unloadedLinkCount &&
        satisfied == shouldSatisfy &&
        promisedSatisfied == shouldPromiseSatisfy &&
        waitingForNetwork == shouldWait) {
      return;
    }

    final notifyOutputs = satisfied != shouldSatisfy;
    _lastReportedLevelInStorage = inStorage;
    satisfied = shouldSatisfy;
    _lastReportedPromises = promised;
    promisedSatisfied = shouldPromiseSatisfy;
    _lastReportedUnloadedLinks = unloadedLinkCount;
    waitingForNetwork = shouldWait;
    panelBE.sendData();
    if (notifyOutputs) notifyRedstoneOutputs();
  }

  /// `tickRequests()`.
  void tickRequests() {
    if (targetedBy.isEmpty && !panelBE.restocker) return;
    if (panelBE.restocker) restockerPromises.tick();
    if (satisfied || promisedSatisfied || waitingForNetwork || redstonePowered)
      return;
    if (_timer > 0) {
      _timer = min(_timer, Lg.i.factoryGaugeTimer);
      _timer--;
      return;
    }

    resetTimer();
    if (recipeAddress.trim().isEmpty) return;

    if (panelBE.restocker) {
      unawaited(tryRestock());
      return;
    }

    unawaited(_requestFromNetwork());
  }

  Future<void> _requestFromNetwork() async {
    var failed = false;
    // network -> (stack identity -> (the input stack and the connections using it))
    final consolidated =
        <String, Map<String, (LStack, List<FactoryPanelConnection>)>>{};

    for (final connection in targetedBy.values) {
      final source = at(panelBE.worldId, connection.from);
      if (source == null) return;
      final item = source.filter.item;
      final byItem = consolidated.putIfAbsent(source.network, () => {});
      final existing = byItem[item.identity];
      if (existing == null) {
        byItem[item.identity] = (item, [connection]);
      } else {
        existing.$2.add(connection);
      }
    }

    final toRequest = <String, List<BigStack>>{};

    for (final entry in consolidated.entries) {
      final network = entry.key;
      final summary = await Lg.i.manager.getSummaryOfNetwork(
        network,
        accurate: true,
      );

      for (final group in entry.value.values) {
        final stack = group.$1;
        final connections = group.$2;
        final total = connections.fold<int>(0, (n, c) => n + c.amount);
        if (total == 0 || stack.isEmpty || summary.countOf(stack) < total) {
          for (final connection in connections) {
            _sendEffect(connection.from, false);
          }
          failed = true;
          continue;
        }
        toRequest.putIfAbsent(network, () => []).add(BigStack(stack, total));
        for (final connection in connections) {
          _sendEffect(connection.from, true);
        }
      }
    }

    if (failed) return;

    var craftingContext = PackageOrderWithCrafts.empty();
    if (activeCraftingArrangement.isNotEmpty) {
      craftingContext = PackageOrderWithCrafts.singleRecipe([
        for (final stack in activeCraftingArrangement)
          BigStack(stack.withCount(1)),
      ]);
    }

    final requests = <Map<PackagerHandle, List<PackagingRequest>>>[];
    for (final entry in toRequest.entries) {
      final order = PackageOrderWithCrafts(
        PackageOrder(entry.value),
        craftingContext.orderedCrafts,
      );
      requests.add(
        await Lg.i.manager.findPackagersForRequest(
          entry.key,
          order,
          null,
          recipeAddress,
        ),
      );
    }

    for (final request in requests) {
      for (final packager in request.keys) {
        if (packager.isTooBusyFor(RequestType.restock)) return;
      }
    }

    for (final request in requests) {
      await Lg.i.manager.performPackageRequests(request);
    }

    final promises = Lg.i.global.getQueuedPromises(network);
    promises?.add(RequestPromise(BigStack(filter.item, recipeOutput)));
  }

  /// `tryRestock()`.
  Future<void> tryRestock() async {
    final item = filter.item;
    if (item.isEmpty) return;

    final packager = panelBE.getRestockedPackager();
    if (packager == null || packager.targetInventory == null) return;

    final available = await Lg.i.manager.getStockOf(
      network,
      item,
      packager.identifiedInventory,
    );
    if (available == 0) {
      _sendEffect(getPanelPosition(), false);
      return;
    }

    final inStorage = getLevelInStorage;
    final promised = getPromised;
    final maxStackSize = item.maxStack;
    final demand = count * (upTo ? 1 : maxStackSize);
    final amountToOrder = (demand - promised - inStorage).clamp(
      0,
      maxStackSize * 9,
    );

    final orderedItem = BigStack(item, min(amountToOrder, available));
    final order = PackageOrderWithCrafts.simple([orderedItem]);

    _sendEffect(getPanelPosition(), true);

    if (!await Lg.i.manager.broadcastPackageRequest(
      network,
      RequestType.restock,
      order,
      packager.identifiedInventory,
      recipeAddress,
    )) {
      return;
    }
    restockerPromises.add(RequestPromise(orderedItem));
  }

  void _sendEffect(FactoryPanelPosition fromPos, bool success) {
    final world = panelBE.world;
    if (world == null) return;
    Lg.i.bus.sendToTracking('create:factory_panel_effect', world, panelBE.pos, {
      'fromPos': fromPos.toMap(),
      'toPos': getPanelPosition().toMap(),
      'success': success,
    });
  }

  /// `addConnection(fromPos)`.
  void addConnection(FactoryPanelPosition fromPos) {
    final link = linkAt(panelBE.worldId, fromPos);
    if (link != null) {
      targetedByLinks[fromPos.pos] = FactoryPanelConnection(fromPos, 1);
      link.connect(apiPosition(getPanelPosition()));
      panelBE.notifyUpdate();
      return;
    }

    if (panelBE.restocker) return;
    if (targetedBy.length >= 9) return;

    final source = at(panelBE.worldId, fromPos);
    if (source == null) return;

    source.targeting.add(getPanelPosition());
    targetedBy[fromPos] = FactoryPanelConnection(fromPos, 1);
    panelBE.notifyUpdate();
  }

  /// `disconnectAll()`.
  void disconnectAll() {
    final position = getPanelPosition();
    disconnectAllLinks();
    for (final connection in targetedBy.values) {
      final source = at(panelBE.worldId, connection.from);
      if (source == null) continue;
      source.targeting.remove(position);
      source.panelBE.sendData();
    }
    for (final targetPosition in targeting) {
      final target = at(panelBE.worldId, targetPosition);
      if (target == null) continue;
      target.targetedBy.remove(position);
      target.panelBE.sendData();
    }
    targetedBy.clear();
    targeting.clear();
  }

  void disconnectAllLinks() {
    for (final connection in targetedByLinks.values) {
      final source = linkAt(panelBE.worldId, connection.from);
      source?.disconnect(apiPosition(getPanelPosition()));
    }
    targetedByLinks.clear();
  }

  /// `getUnloadedLinks()`.
  int get getUnloadedLinks {
    if (panelBE.restocker)
      return panelBE.getRestockedPackager() == null ? 1 : 0;
    return Lg.i.global.getUnloadedLinkCount(network);
  }

  /// `getLevelInStorage()`.
  int get getLevelInStorage {
    if (filter.item.isEmpty) return 0;
    return _relevantSummary().countOf(filter.item);
  }

  InventorySummary? _cachedSummary;

  InventorySummary _relevantSummary() {
    // `getRelevantSummary` is asynchronous on the host; the last summary is used and refreshed
    // by [_refreshRelevantSummary] from [tickRequests].
    unawaited(_refreshRelevantSummary());
    return _cachedSummary ?? InventorySummary();
  }

  Future<void> _refreshRelevantSummary() async {
    if (panelBE.restocker) {
      final packager = panelBE.getRestockedPackager();
      _cachedSummary = packager == null
          ? InventorySummary()
          : await packager.getAvailableItems();
      return;
    }
    _cachedSummary = await Lg.i.manager.getSummaryOfNetwork(
      network,
      accurate: false,
    );
  }

  /// `getPromised()`.
  int get getPromised {
    final item = filter.item;
    if (item.isEmpty) return 0;

    if (panelBE.restocker) {
      if (forceClearPromises) {
        restockerPromises.forceClear(item);
        resetTimerSlightly();
      }
      forceClearPromises = false;
      return restockerPromises.getTotalPromisedAndRemoveExpired(
        item,
        promiseExpiryTicks,
      );
    }

    final promises = Lg.i.global.getQueuedPromises(network);
    if (promises == null) return 0;

    if (forceClearPromises) {
      promises.forceClear(item);
      resetTimerSlightly();
    }
    forceClearPromises = false;
    return promises.getTotalPromisedAndRemoveExpired(item, promiseExpiryTicks);
  }

  void resetTimer() => _timer = Lg.i.factoryGaugeTimer;

  void resetTimerSlightly() => _timer = Lg.i.factoryGaugeTimer ~/ 2;

  int get promiseExpiryTicks {
    if (promiseClearingInterval == -1) return -1;
    if (promiseClearingInterval == 0) return 20 * 30;
    return promiseClearingInterval * 20 * 60;
  }

  // -- state -----------------------------------------------------------------------------------

  Map<String, dynamic> toMap() => {
    'Filter': filter.item.isEmpty ? null : filter.item.toJson(),
    'FilterAmount': count,
    'UpTo': upTo,
    'Timer': _timer,
    'LastLevel': _lastReportedLevelInStorage,
    'LastPromised': _lastReportedPromises,
    'LastUnloadedLinks': _lastReportedUnloadedLinks,
    'Satisfied': satisfied,
    'PromisedSatisfied': promisedSatisfied,
    'Waiting': waitingForNetwork,
    'RedstonePowered': redstonePowered,
    'RecipeAddress': recipeAddress,
    'RecipeOutput': recipeOutput,
    'PromiseClearingInterval': promiseClearingInterval,
    'Freq': network,
    'Craft': [for (final s in activeCraftingArrangement) s.toJson()],
    'Targeting': [for (final p in targeting) p.toMap()],
    'TargetedBy': [for (final c in targetedBy.values) c.toMap()],
    'TargetedByLinks': [for (final c in targetedByLinks.values) c.toMap()],
    'Promises': panelBE.restocker
        ? [for (final p in restockerPromises.toList()) p.toMap()]
        : null,
  };

  void readFromMap(Map<String, dynamic> map) {
    active = true;
    filter = map['Filter'] is String
        ? FilterItemStack.fromJson(map['Filter'] as String, wire: Lg.i.wire)
        : FilterItemStack.empty;
    count = map['FilterAmount'] as int? ?? 0;
    upTo = map['UpTo'] as bool? ?? false;
    _timer = map['Timer'] as int? ?? 0;
    _lastReportedLevelInStorage = map['LastLevel'] as int? ?? 0;
    _lastReportedPromises = map['LastPromised'] as int? ?? 0;
    _lastReportedUnloadedLinks = map['LastUnloadedLinks'] as int? ?? 0;
    satisfied = map['Satisfied'] as bool? ?? false;
    promisedSatisfied = map['PromisedSatisfied'] as bool? ?? false;
    waitingForNetwork = map['Waiting'] as bool? ?? false;
    redstonePowered = map['RedstonePowered'] as bool? ?? false;
    recipeAddress = map['RecipeAddress'] as String? ?? '';
    recipeOutput = map['RecipeOutput'] as int? ?? 1;
    promiseClearingInterval = map['PromiseClearingInterval'] as int? ?? -1;
    network = map['Freq'] as String? ?? network;

    activeCraftingArrangement = [
      for (final s in (map['Craft'] as List<dynamic>? ?? const []))
        if (s is String) LStackMapper.fromJson(s),
    ];
    targeting
      ..clear()
      ..addAll([
        for (final p in (map['Targeting'] as List<dynamic>? ?? const []))
          if (FactoryPanelPosition.fromMap(p) case final position?) position,
      ]);
    targetedBy.clear();
    for (final c in (map['TargetedBy'] as List<dynamic>? ?? const [])) {
      final connection = FactoryPanelConnection.fromMap(c);
      if (connection != null) targetedBy[connection.from] = connection;
    }
    targetedByLinks.clear();
    for (final c in (map['TargetedByLinks'] as List<dynamic>? ?? const [])) {
      final connection = FactoryPanelConnection.fromMap(c);
      if (connection != null) targetedByLinks[connection.from.pos] = connection;
    }
    if (map['Promises'] is List) {
      restockerPromises = RequestPromiseQueue.fromList([
        for (final p in map['Promises'] as List<dynamic>)
          if (p is Map) RequestPromiseMapper.fromMap(p.cast<String, dynamic>()),
      ], () => panelBE.markDirty());
    }
  }
}

// -- NBT helpers for the panel compounds ---------------------------------------------------------

NbtCompound _positionToNbt(FactoryPanelPosition position) => NbtCompound()
  ..putIntArray('pos', [position.pos.$1, position.pos.$2, position.pos.$3])
  ..putString('slot', position.slot.serializedName);

FactoryPanelPosition? _positionFromNbt(NbtCompound tag) {
  final pos = tag.getIntArray('pos');
  final slot = PanelSlot.byName(tag.getString('slot') ?? '');
  if (pos == null || pos.length < 3 || slot == null) return null;
  return FactoryPanelPosition((pos[0], pos[1], pos[2]), slot);
}

NbtCompound _connectionToNbt(FactoryPanelConnection connection) => NbtCompound()
  ..putCompound('position', _positionToNbt(connection.from))
  ..putInt('amount', connection.amount)
  ..putInt('arrow_bending', connection.arrowBendMode);

FactoryPanelConnection? _connectionFromNbt(NbtCompound tag) {
  final position = tag.getCompound('position');
  if (position == null) return null;
  final from = _positionFromNbt(position);
  if (from == null) return null;
  return FactoryPanelConnection(
    from,
    tag.getInt('amount') ?? 0,
    tag.getInt('arrow_bending') ?? -1,
  );
}
