// `LogisticsManager` and the link directory of `LogisticallyLinkedBehaviour` (pure): which
// links serve a network, the cached summaries of a network and how a package order is split
// over the packagers that have the items. The block entities implement [LogisticsLink] and
// [PackagerHandle]; the algorithm below is a line by line port.
import 'dart:math';

import 'inventory.dart';
import 'orders.dart';
import 'stack.dart';

/// `LogisticallyLinkedBehaviour.RequestType`.
enum RequestType { restock, redstone, player }

/// A packager as the manager drives it (`PackagerBlockEntity`).
abstract interface class PackagerHandle {
  /// `isTooBusyFor(type)`.
  bool isTooBusyFor(RequestType type);

  /// `flashLink()`.
  void flashLink();

  /// `attemptToSend(queuedRequests)`: sends packages for the head of the list (and removes
  /// finished requests from it).
  Future<void> attemptToSend(List<PackagingRequest> queuedRequests);

  /// `triggerStockCheck()`.
  Future<void> triggerStockCheck();

  /// `notifyUpdate()`.
  void notifyUpdate();
}

/// The answer of `LogisticallyLinkedBehaviour.processRequest`: the packager and its request.
final class LinkRequest {
  final PackagerHandle packager;
  final PackagingRequest request;

  const LinkRequest(this.packager, this.request);
}

/// A link of a network (`LogisticallyLinkedBehaviour`): a stock link, or a stock checking block
/// (stock ticker, redstone requester) that is not part of the global registry.
abstract interface class LogisticsLink {
  /// The network the link belongs to.
  String get freqId;

  /// `redstonePower`: 15 disables the link; lower power is asked first.
  int get redstonePower;

  /// `!blockEntity.isRemoved() && !blockEntity.isChunkUnloaded()`.
  bool get isValid;

  /// `getInventoryIdentifierFromLink`: the identifier of the inventory behind the link's
  /// packager, `null` if unknown or there is no packager.
  InventoryIdentifier? get inventoryIdentifier;

  /// `getSummary(ignoredHandler)`.
  Future<InventorySummary> getSummary(IdentifiedInventory? ignored);

  /// `processRequest(...)`.
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

  /// `deductFromAccurateSummary(packageContents)`.
  void deductFromAccurateSummary(List<LStack> packageContents);
}

/// `TickBasedCache`: entries expire [expiry] ticks after they were written.
class TickCache<K, V> {
  final int expiry;
  final int Function() _now;
  final Map<K, (V, int)> _map = {};

  TickCache(this.expiry, this._now);

  V? getIfPresent(K key) {
    final e = _map[key];
    if (e == null) return null;
    if (_now() - e.$2 >= expiry) {
      _map.remove(key);
      return null;
    }
    return e.$1;
  }

  V get(K key, V Function() create) {
    final existing = getIfPresent(key);
    if (existing != null) return existing;
    final v = create();
    _map[key] = (v, _now());
    return v;
  }

  void put(K key, V value) => _map[key] = (value, _now());

  void invalidate(K key) => _map.remove(key);

  void clear() => _map.clear();
}

/// The static `LINKS` cache of `LogisticallyLinkedBehaviour`: links by network and link id; a
/// link that is not kept alive for 400 ticks drops out.
class LinkDirectory {
  /// Ticks without `keepAlive` after which a link is forgotten.
  static const int linkExpiry = 400;

  final int Function() _now;
  final Map<String, Map<int, (LogisticsLink, int)>> _links = {};
  int _nextId = 0;

  LinkDirectory(this._now);

  /// `LINK_ID_GENERATOR.getAndIncrement()`.
  int newLinkId() => _nextId++;

  /// `getAllPresent(freq, sortByPriority)`.
  List<LogisticsLink> getAllPresent(String freq, {bool sortByPriority = false}) {
    final cache = _links[freq];
    if (cache == null) return const [];
    final now = _now();
    cache.removeWhere((_, e) => now - e.$2 >= linkExpiry);
    var list = [for (final e in cache.values) if (e.$1.isValid) e.$1];
    if (sortByPriority) {
      final indexed = list.asMap().entries.toList()
        ..sort((a, b) {
          final c = a.value.redstonePower.compareTo(b.value.redstonePower);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      list = [for (final e in indexed) e.value];
    }
    return list;
  }

  /// `keepAlive(behaviour)`: not for links at redstone power 15.
  void keepAlive(int linkId, LogisticsLink link) {
    if (link.redstonePower == 15) return;
    _links.putIfAbsent(link.freqId, () => {})[linkId] = (link, _now());
  }

  /// `remove(behaviour)`.
  void remove(int linkId, String freqId) {
    _links[freqId]?.remove(linkId);
  }

  void clear() => _links.clear();
}

/// `LogisticsManager`.
class LogisticsManager {
  final LinkDirectory links;
  final Random random;
  late final TickCache<String, InventorySummary> accurateSummaries;
  late final TickCache<String, InventorySummary> summaries;

  LogisticsManager(this.links, int Function() now, {Random? random}) : random = random ?? Random() {
    accurateSummaries = TickCache(1, now);
    summaries = TickCache(20, now);
  }

  /// `getSummaryOfNetwork(freqId, accurate)`.
  Future<InventorySummary> getSummaryOfNetwork(String freqId, {required bool accurate}) async {
    final cache = accurate ? accurateSummaries : summaries;
    final cached = cache.getIfPresent(freqId);
    if (cached != null) return cached;
    final created = await _createSummaryOfNetwork(freqId);
    cache.put(freqId, created);
    return created;
  }

  Future<InventorySummary> _createSummaryOfNetwork(String freqId) async {
    final summaryOfLinks = InventorySummary();
    final processed = <InventoryIdentifier>{};
    for (final link in links.getAllPresent(freqId)) {
      // Skip inventories already presented by other links.
      final id = link.inventoryIdentifier;
      if (id != null && !processed.add(id)) continue;
      final summary = await link.getSummary(null);
      if (!identical(summary, InventorySummary.empty)) {
        summaryOfLinks.contributingLinks++;
        summaryOfLinks.addSummary(summary);
      }
    }
    return summaryOfLinks;
  }

  /// `getStockOf(freqId, stack, ignoredHandler)`.
  Future<int> getStockOf(String freqId, LStack stack, IdentifiedInventory? ignored) async {
    var sum = 0;
    for (final link in links.getAllPresent(freqId)) {
      sum += (await link.getSummary(ignored)).countOf(stack);
    }
    return sum;
  }

  /// `broadcastPackageRequest`: false when the order is empty or a packager is too busy.
  Future<bool> broadcastPackageRequest(
    String freqId,
    RequestType type,
    PackageOrderWithCrafts order,
    IdentifiedInventory? ignored,
    String address,
  ) async {
    if (order.isEmpty) return false;
    final requests = await findPackagersForRequest(freqId, order, ignored, address);
    // Check if packagers have accumulated too many packages already.
    for (final packager in requests.keys) {
      if (packager.isTooBusyFor(type)) return false;
    }
    await performPackageRequests(requests);
    return true;
  }

  /// `findPackagersForRequest`.
  Future<Map<PackagerHandle, List<PackagingRequest>>> findPackagersForRequest(
    String freqId,
    PackageOrderWithCrafts order,
    IdentifiedInventory? ignored,
    String address,
  ) async {
    final stacks = [for (final s in order.stacks) if (s.stack.isNotEmpty && s.count > 0) s];
    final requests = <PackagerHandle, List<PackagingRequest>>{};

    // Group links by inventory identifier and randomly select one from each group.
    final all = links.getAllPresent(freqId, sortByPriority: true);
    final linksByInventory = <InventoryIdentifier, List<LogisticsLink>>{};
    final availableLinks = <LogisticsLink>[];
    for (final link in all) {
      final id = link.inventoryIdentifier;
      if (id != null) {
        linksByInventory.putIfAbsent(id, () => []).add(link);
      } else {
        availableLinks.add(link);
      }
    }
    for (final group in linksByInventory.values) {
      if (group.isNotEmpty) availableLinks.add(group[random.nextInt(group.length)]);
    }

    final usedLinks = <LogisticsLink>[];
    var finalLinkTracker = MutableFlag(false);
    // First box needs to carry the order specifics for successful defrag.
    PackageOrderWithCrafts? context = order;
    // Packages from future orders should not be merged in the packager queue.
    final orderId = random.nextInt(1 << 32).toSigned(32);

    for (var i = 0; i < stacks.length; i++) {
      final entry = stacks[i];
      var remainingCount = entry.count;
      final finalEntry = i == stacks.length - 1;
      final requestedItem = entry.stack;
      for (final link in availableLinks) {
        final usedIndex = usedLinks.indexOf(link);
        final linkIndex = usedIndex == -1 ? usedLinks.length : usedIndex;
        var isFinalLink = MutableFlag(false);
        if (linkIndex == usedLinks.length - 1) isFinalLink = finalLinkTracker;
        // Only send context and craftingContext with the first package.
        final request = await link.processRequest(requestedItem, remainingCount, address, linkIndex, isFinalLink, orderId, context, ignored);
        if (request == null) continue;
        requests.putIfAbsent(request.packager, () => []).add(request.request);
        final processedCount = request.request.count;
        if (processedCount > 0 && usedIndex == -1) {
          context = null;
          usedLinks.add(link);
          finalLinkTracker = isFinalLink;
        }
        remainingCount -= processedCount;
        if (remainingCount > 0) continue;
        if (finalEntry) finalLinkTracker.value = true;
        break;
      }
    }
    return requests;
  }

  /// `performPackageRequests`.
  Future<void> performPackageRequests(Map<PackagerHandle, List<PackagingRequest>> requests) async {
    for (final entry in requests.entries) {
      final queued = List<PackagingRequest>.of(entry.value);
      final packager = entry.key;
      if (queued.isNotEmpty) packager.flashLink();
      for (var i = 0; i < 100; i++) {
        if (queued.isEmpty) break;
        await packager.attemptToSend(queued);
      }
      await packager.triggerStockCheck();
      packager.notifyUpdate();
    }
  }
}
