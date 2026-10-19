// `FactoryPanelBehaviour`: one gauge of a factory panel, its connections to other gauges and its
// restock/request loop.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../filter/filter_item_stack.dart';
import '../filter/filtering_behaviour.dart';
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

  Map<String, dynamic> toMap() => {
    'pos': [pos.$1, pos.$2, pos.$3],
    'slot': slot.serializedName,
  };

  static FactoryPanelPosition? fromMap(Object? value) {
    if (value is! Map) return null;
    final p = value['pos'];
    final slot = PanelSlot.byName(value['slot'] as String? ?? '');
    if (p is! List || p.length != 3 || slot == null) return null;
    return FactoryPanelPosition((p[0] as int, p[1] as int, p[2] as int), slot);
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
    'from': from.toMap(),
    'amount': amount,
    'arrow_bend_mode': arrowBendMode,
  };

  static FactoryPanelConnection? fromMap(Object? value) {
    if (value is! Map) return null;
    final from = FactoryPanelPosition.fromMap(value['from']);
    if (from == null) return null;
    return FactoryPanelConnection(
      from,
      value['amount'] as int? ?? 0,
      value['arrow_bend_mode'] as int? ?? -1,
    );
  }
}

/// `FactoryPanelSupportBehaviour`: the link of a non-gauge block that a gauge can be wired to.
/// The blocks of the redstone module that own this behaviour are outside this module; the panel
/// side still resolves it when such a block provides it.
class FactoryPanelSupportBehaviour extends BlockEntityBehaviour {
  static const String behaviourId = 'FactoryPanelSupport';

  final List<FactoryPanelPosition> linkedPanels = [];
  bool changed = false;
  final bool Function() isOutput;
  final bool Function() outputPower;
  final void Function() onNotify;

  FactoryPanelSupportBehaviour(this.isOutput, this.outputPower, this.onNotify);

  @override
  String get id => behaviourId;

  bool get shouldPanelBePowered => isOutput() && outputPower();

  void notifyLink() => onNotify();

  void connect(FactoryPanelBehaviour panel) {
    final position = panel.getPanelPosition();
    if (linkedPanels.contains(position)) return;
    linkedPanels.add(position);
    changed = true;
  }

  void disconnect(FactoryPanelBehaviour panel) {
    linkedPanels.remove(panel.getPanelPosition());
    changed = true;
  }

  void notifyPanels() {
    if (owner.world == null) return;
    for (final position in List.of(linkedPanels)) {
      if (!owner.world!.isLoaded(pos: position.pos.toBlockPos())) continue;
      final behaviour = FactoryPanelBehaviour.at(owner.worldId, position);
      if (behaviour == null) {
        linkedPanels.remove(position);
        changed = true;
        continue;
      }
      behaviour.checkForRedstoneInput();
    }
  }

  @override
  void tick() {
    super.tick();
    if (!changed) return;
    changed = false;
    if (!isOutput()) notifyLink();
    owner.markDirty();
  }
}

/// `FactoryPanelBehaviour`.
class FactoryPanelBehaviour extends FilteringBehaviour {
  final FactoryPanelBlockEntity panelBE;
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

  /// `FactoryPanelBehaviour.linkAt(world, position)`.
  static FactoryPanelSupportBehaviour? linkAt(
    String worldId,
    FactoryPanelPosition position,
  ) {
    final be = Lg.i.store.at(worldId, position.pos.toBlockPos());
    return be?.getBehaviour<FactoryPanelSupportBehaviour>();
  }

  static FactoryPanelSupportBehaviour? linkAtConnection(
    String worldId,
    FactoryPanelConnection connection,
  ) => linkAt(worldId, connection.from);

  FactoryPanelPosition getPanelPosition() =>
      FactoryPanelPosition(panelBE.pos.toPos(), slot);

  @override
  bool get isActive => active;

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

  @override
  void initialize() {
    super.initialize();
    notifyRedstoneOutputs();
  }

  @override
  void tick() {
    super.tick();
    tickStorageMonitor();
    tickRequests();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    checkForRedstoneInput();
  }

  // The panel state is saved as JSON by [FactoryPanelBlockEntity] (all four gauges share one NBT
  // tag, so the filtering behaviour's flat keys would collide).
  @override
  void write(NbtCompound tag, {required bool clientPacket}) {}

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {}

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
      if (link == null || link.isOutput()) return;
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
      link.connect(this);
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
      source?.disconnect(this);
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
    'slot': slot.serializedName,
    'filter': filter.item.isEmpty ? null : filter.item.toJson(),
    'filterAmount': count,
    'upTo': upTo,
    'timer': _timer,
    'lastLevel': _lastReportedLevelInStorage,
    'lastPromised': _lastReportedPromises,
    'lastUnloadedLinks': _lastReportedUnloadedLinks,
    'satisfied': satisfied,
    'promisedSatisfied': promisedSatisfied,
    'waiting': waitingForNetwork,
    'redstonePowered': redstonePowered,
    'recipeAddress': recipeAddress,
    'recipeOutput': recipeOutput,
    'promiseClearingInterval': promiseClearingInterval,
    'network': network,
    'craft': [for (final s in activeCraftingArrangement) s.toJson()],
    'targeting': [for (final p in targeting) p.toMap()],
    'targetedBy': [for (final c in targetedBy.values) c.toMap()],
    'targetedByLinks': [for (final c in targetedByLinks.values) c.toMap()],
    'promises': panelBE.restocker
        ? [for (final p in restockerPromises.toList()) p.toMap()]
        : null,
  };

  void readFromMap(Map<String, dynamic> map) {
    active = true;
    slot = PanelSlot.byName(map['slot'] as String? ?? '') ?? slot;
    filter = map['filter'] is String
        ? FilterItemStack.fromJson(map['filter'] as String, wire: Lg.i.wire)
        : FilterItemStack.empty;
    count = map['filterAmount'] as int? ?? 0;
    upTo = map['upTo'] as bool? ?? false;
    _timer = map['timer'] as int? ?? 0;
    _lastReportedLevelInStorage = map['lastLevel'] as int? ?? 0;
    _lastReportedPromises = map['lastPromised'] as int? ?? 0;
    _lastReportedUnloadedLinks = map['lastUnloadedLinks'] as int? ?? 0;
    satisfied = map['satisfied'] as bool? ?? false;
    promisedSatisfied = map['promisedSatisfied'] as bool? ?? false;
    waitingForNetwork = map['waiting'] as bool? ?? false;
    redstonePowered = map['redstonePowered'] as bool? ?? false;
    recipeAddress = map['recipeAddress'] as String? ?? '';
    recipeOutput = map['recipeOutput'] as int? ?? 1;
    promiseClearingInterval = map['promiseClearingInterval'] as int? ?? -1;
    network = map['network'] as String? ?? network;

    activeCraftingArrangement = [
      for (final s in (map['craft'] as List<dynamic>? ?? const []))
        if (s is String) LStackMapper.fromJson(s),
    ];
    targeting
      ..clear()
      ..addAll([
        for (final p in (map['targeting'] as List<dynamic>? ?? const []))
          if (FactoryPanelPosition.fromMap(p) case final position?) position,
      ]);
    targetedBy.clear();
    for (final c in (map['targetedBy'] as List<dynamic>? ?? const [])) {
      final connection = FactoryPanelConnection.fromMap(c);
      if (connection != null) targetedBy[connection.from] = connection;
    }
    targetedByLinks.clear();
    for (final c in (map['targetedByLinks'] as List<dynamic>? ?? const [])) {
      final connection = FactoryPanelConnection.fromMap(c);
      if (connection != null) targetedByLinks[connection.from.pos] = connection;
    }
    if (map['promises'] is List) {
      restockerPromises = RequestPromiseQueue.fromList([
        for (final p in map['promises'] as List<dynamic>)
          if (p is Map) RequestPromiseMapper.fromMap(p.cast<String, dynamic>()),
      ], () => panelBE.markDirty());
    }
  }
}
