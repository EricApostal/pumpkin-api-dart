// The logistics networks (pure): promises, `LogisticsNetwork`, `GlobalLogisticsManager` and the
// saved data they persist in. Network ids are UUID strings (`LogisticallyLinkedBehaviour.freqId`).
import 'package:dart_mappable/dart_mappable.dart';

import 'stack.dart';

part 'network.mapper.dart';

/// `RequestPromise`: items a package order or a factory panel announced that did not arrive yet.
@MappableClass()
class RequestPromise with RequestPromiseMappable {
  int ticksExisted;
  BigStack promisedStack;

  RequestPromise(this.promisedStack, [this.ticksExisted = 0]);

  void tick() => ticksExisted++;

  /// `ageComparator`: oldest first.
  static int compareByAge(RequestPromise a, RequestPromise b) => b.ticksExisted.compareTo(a.ticksExisted);
}

/// `RequestPromiseQueue`.
class RequestPromiseQueue {
  final Map<String, List<RequestPromise>> _byItem = {};
  void Function() _onChanged;

  RequestPromiseQueue(this._onChanged);

  set onChanged(void Function() callback) => _onChanged = callback;

  void add(RequestPromise promise) {
    _byItem.putIfAbsent(promise.promisedStack.stack.key, () => []).add(promise);
    _onChanged();
  }

  /// `getTotalPromisedAndRemoveExpired(stack, expiryTime)`; an expiry of -1 never expires.
  int getTotalPromisedAndRemoveExpired(LStack stack, int expiryTime) {
    var promised = 0;
    final list = _byItem[stack.key];
    if (list == null) return promised;
    for (final promise in List.of(list)) {
      if (!promise.promisedStack.stack.sameItemSameComponents(stack)) continue;
      if (expiryTime != -1 && promise.ticksExisted >= expiryTime) {
        list.remove(promise);
        _onChanged();
        continue;
      }
      promised += promise.promisedStack.count;
    }
    return promised;
  }

  /// `forceClear(stack)`.
  void forceClear(LStack stack) {
    final list = _byItem[stack.key];
    if (list == null) return;
    for (final promise in List.of(list)) {
      if (!promise.promisedStack.stack.sameItemSameComponents(stack)) continue;
      list.remove(promise);
      _onChanged();
    }
    if (list.isEmpty) _byItem.remove(stack.key);
  }

  /// `itemEnteredSystem(stack, amount)`: arrived items fulfil promises, oldest added first.
  void itemEnteredSystem(LStack stack, int amount) {
    final list = _byItem[stack.key];
    if (list == null) return;
    var remaining = amount;
    for (final promise in List.of(list)) {
      if (!promise.promisedStack.stack.sameItemSameComponents(stack)) continue;
      final toSubtract = remaining < promise.promisedStack.count ? remaining : promise.promisedStack.count;
      remaining -= toSubtract;
      promise.promisedStack.count -= toSubtract;
      if (promise.promisedStack.count <= 0) {
        list.remove(promise);
        _onChanged();
      }
      if (remaining <= 0) break;
    }
    if (list.isEmpty) _byItem.remove(stack.key);
  }

  /// `flatten(sorted)`.
  List<RequestPromise> flatten({bool sorted = false}) {
    final all = [for (final l in _byItem.values) ...l];
    if (sorted) {
      final indexed = all.asMap().entries.toList()
        ..sort((a, b) {
          final c = RequestPromise.compareByAge(a.value, b.value);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      return [for (final e in indexed) e.value];
    }
    return all;
  }

  /// `tick()`: every promise gets older.
  void tick() {
    for (final list in _byItem.values) {
      for (final p in list) {
        p.tick();
      }
    }
  }

  bool get isEmpty => _byItem.isEmpty;

  /// `write` as the list of promises.
  List<RequestPromise> toList() => flatten();

  /// `read`: [onChanged] is not called while loading.
  static RequestPromiseQueue fromList(Iterable<RequestPromise> promises, void Function() onChanged) {
    final queue = RequestPromiseQueue(() {});
    for (final p in promises) {
      queue.add(p);
    }
    queue._onChanged = onChanged;
    return queue;
  }
}

/// `GlobalPos`: a position in a dimension.
@MappableClass()
class GlobalPos with GlobalPosMappable {
  final String dimension;
  final int x;
  final int y;
  final int z;

  const GlobalPos(this.dimension, this.x, this.y, this.z);

  @override
  bool operator ==(Object other) => other is GlobalPos && other.dimension == dimension && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(dimension, x, y, z);
}

/// `LogisticsNetwork`.
class LogisticsNetwork {
  final String id;
  late RequestPromiseQueue panelPromises;
  final Set<GlobalPos> totalLinks = {};
  final Set<GlobalPos> loadedLinks = {};
  String? owner;
  bool locked = false;

  LogisticsNetwork(this.id, void Function() markDirty) {
    panelPromises = RequestPromiseQueue(markDirty);
  }
}

/// The persisted form of a network (`LogisticsNetwork.write`).
@MappableClass()
class LogisticsNetworkData with LogisticsNetworkDataMappable {
  final String id;
  final List<RequestPromise> promises;
  final List<GlobalPos> links;
  final String? owner;
  final bool locked;

  const LogisticsNetworkData(this.id, this.promises, this.links, this.owner, this.locked);
}

/// `LogisticsNetworkSavedData`: everything the manager persists (`create_logistics`).
@MappableClass()
class LogisticsSavedData with LogisticsSavedDataMappable {
  final List<LogisticsNetworkData> logisticsNetworks;

  const LogisticsSavedData([this.logisticsNetworks = const []]);
}

/// `GlobalLogisticsManager` (`Create.LOGISTICS`): which links belong to which network, who owns
/// and may use it, and the promises of the factory panels. [onDirty] saves the data.
class GlobalLogisticsManager {
  final Map<String, LogisticsNetwork> logisticsNetworks = {};
  void Function() onDirty;

  GlobalLogisticsManager({void Function()? onDirty}) : onDirty = onDirty ?? (() {});

  void markDirty() => onDirty();

  LogisticsNetwork _create(String id) => LogisticsNetwork(id, markDirty);

  /// `mayInteract(networkId, player)`.
  bool mayInteract(String networkId, String playerUuid) {
    final network = logisticsNetworks[networkId];
    return network == null || network.owner == null || !network.locked || network.owner == playerUuid;
  }

  /// `mayAdministrate`.
  bool mayAdministrate(String networkId, String playerUuid) {
    final network = logisticsNetworks[networkId];
    return network == null || network.owner == null || network.owner == playerUuid;
  }

  /// `isLockable`.
  bool isLockable(String networkId) => logisticsNetworks.containsKey(networkId);

  /// `isLocked`.
  bool isLocked(String networkId) => logisticsNetworks[networkId]?.locked ?? false;

  /// `linkAdded(networkId, pos, ownedBy)`.
  void linkAdded(String networkId, GlobalPos pos, String? ownedBy) {
    final network = logisticsNetworks.putIfAbsent(networkId, () => _create(networkId));
    network.totalLinks.add(pos);
    if (ownedBy != null && network.owner == null) network.owner = ownedBy;
    markDirty();
  }

  /// `linkLoaded`.
  void linkLoaded(String networkId, GlobalPos pos) {
    logisticsNetworks.putIfAbsent(networkId, () => _create(networkId)).loadedLinks.add(pos);
  }

  /// `linkRemoved`.
  void linkRemoved(String networkId, GlobalPos pos) {
    final network = logisticsNetworks[networkId];
    if (network == null) return;
    network.totalLinks.remove(pos);
    network.loadedLinks.remove(pos);
    if (network.totalLinks.isEmpty) logisticsNetworks.remove(networkId);
    markDirty();
  }

  /// `linkInvalidated`: the link unloaded.
  void linkInvalidated(String networkId, GlobalPos pos) {
    logisticsNetworks[networkId]?.loadedLinks.remove(pos);
  }

  /// `getUnloadedLinkCount`.
  int getUnloadedLinkCount(String networkId) {
    final n = logisticsNetworks[networkId];
    return n == null ? 0 : n.totalLinks.length - n.loadedLinks.length;
  }

  /// `getQueuedPromises`.
  RequestPromiseQueue? getQueuedPromises(String networkId) => logisticsNetworks[networkId]?.panelPromises;

  /// `hasQueuedPromises`.
  bool hasQueuedPromises(String networkId) {
    final n = logisticsNetworks[networkId];
    return n != null && !n.panelPromises.isEmpty;
  }

  /// `tick(level)`: only for the overworld (the caller checks).
  void tick() {
    for (final n in logisticsNetworks.values) {
      n.panelPromises.tick();
    }
  }

  /// `loadLogisticsData`: replaces the networks with the saved ones.
  void load(LogisticsSavedData data) {
    logisticsNetworks.clear();
    for (final d in data.logisticsNetworks) {
      final n = _create(d.id);
      n.panelPromises = RequestPromiseQueue.fromList(d.promises, markDirty);
      n.totalLinks.addAll(d.links);
      n.owner = d.owner;
      n.locked = d.locked;
      logisticsNetworks[d.id] = n;
    }
  }

  /// `LogisticsNetworkSavedData.save`.
  LogisticsSavedData save() => LogisticsSavedData([
    for (final n in logisticsNetworks.values)
      LogisticsNetworkData(n.id, n.panelPromises.toList(), n.totalLinks.toList(), n.owner, n.locked),
  ]);
}
