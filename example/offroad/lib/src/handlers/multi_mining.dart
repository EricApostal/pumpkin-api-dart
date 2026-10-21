// `MultiMiningServerManager`: the per-tick state machine of the multi-block
// mining the borehead bearing does. Several bearings may cut the same block; the
// progress of that block is advanced by the average breaking speed of the
// suppliers that are still active, and reset once none of them is.
//
// The state machine is deterministic and takes its randomness (the supplier
// shuffle before a drop is handed out) from an injected `Random`, so the tests
// can seed it.
//
// The world is behind [MultiMiningLevel]: the manager never touches it directly,
// which keeps this file on the VM. The two level calls that touch the world
// (`destroyBlock`, `popResource`) are asynchronous because the host's are
// (`BlockHelper.destroyBlockWith`, `World.dropItem`); everything else is a plain
// function of the state.
//
// Pure: no host imports.
//
// Java: `handlers/server/MultiMiningServerManager.java`,
//       `handlers/MultiminingDataTickResult.java`,
//       `handlers/server/MultiMiningSupplier.java`
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/common.dart' show Pos;

import '../network/borehead_sync_packet.dart';

/// `MultiminingDataTickResult` (`handlers/MultiminingDataTickResult.java:3`).
enum MultiMiningTickResult {
  /// The progress advanced; the data stays.
  continueTicking,

  /// The position stopped being mined (nothing left to mine, no supplier, or a
  /// timeout): the progress is reset and the data dropped.
  stop,

  /// The block was destroyed.
  broken,
}

/// A drop of a destroyed block (`ItemStack`).
final class MinedDrop {
  final String itemKey;
  final int count;

  const MinedDrop(this.itemKey, this.count);

  /// `stack.isEmpty()`.
  bool get isEmpty => count <= 0;
}

/// `MultiMiningSupplier` (`handlers/server/MultiMiningSupplier.java:10`).
abstract interface class MultiMiningSupplier {
  /// `getBreakingSpeed(level, pos, currentState)`.
  double breakingSpeed(Pos pos, String blockKey);

  /// `isActive()`: an inactive supplier is dropped from the position, and the
  /// position stalls once none is left.
  bool get isActive;

  /// `getLocation()`: where the supplier is, for the sync payload.
  Pos? get location;

  /// `itemCallback(stack)`: offer up to [count] items to the supplier; returns
  /// how many it took (`ItemStack.shrink(inserted)`).
  int acceptItem(String itemKey, int count);
}

/// What the manager needs of a level (`Level`).
abstract interface class MultiMiningLevel {
  /// The block key at [pos].
  String blockKeyAt(Pos pos);

  /// `state.getDestroySpeed(level, pos)`.
  double hardnessAt(Pos pos);

  /// `BlockBreakingKineticBlockEntity.isBreakable(state, hardness)` and the
  /// state is not air (`MultiMiningServerManager.java:180`).
  bool isBreakableAt(Pos pos);

  /// `BlockHelper.destroyBlock(level, pos, 1, consumer)`: the drops of [pos].
  /// The caller is responsible for the `1` (no tool) drop behaviour.
  ///
  /// Asynchronous because the host breaks a block through an async call
  /// (`BlockHelper.destroyBlockWith`); the Java consumer is synchronous.
  Future<List<MinedDrop>> destroyBlock(Pos pos);

  /// `Block.popResource(level, pos, stack)`: a drop nobody accepted.
  Future<void> popResource(Pos pos, MinedDrop drop);
}

/// `BlockBreakingData` (`MultiMiningServerManager.java:133`): the breaking state
/// of one block position.
final class BlockBreakingData {
  /// `MAX_TIMEOUT` (`MultiMiningServerManager.java:135`).
  static const int maxTimeout = 20;

  /// The position being broken.
  final Pos breakingPos;

  /// The suppliers giving this position its speed (`usually a borehead bearing`).
  final List<MultiMiningSupplier> suppliers = [];

  /// Ticks since the last supplier refreshed this position.
  double timeoutTicks = 0;

  /// The destruction progress, 0 to 10 with 10 meaning broken.
  double destroyProgress = 0;

  /// Where the first supplier was when it was last ticked.
  Pos? lastKnownSupplierPosition;

  BlockBreakingData(this.breakingPos);

  /// The progress as the `byte` the packet carries (`getDestroyProgressByted`).
  ///
  /// Java casts the float to a byte, which truncates towards zero and takes the
  /// low eight bits, then sign-extends; the unsigned value is compared here so
  /// `-1` and `-1` still compare equal.
  int get destroyProgressByte => destroyProgress.truncate() & 0xFF;

  /// `addSupplier(supplier, refreshTimeout)` (`MultiMiningServerManager.java:221`).
  void addSupplier(MultiMiningSupplier supplier, {required bool refreshTimeout}) {
    if (!suppliers.contains(supplier)) suppliers.add(supplier);
    if (refreshTimeout) timeoutTicks = 0;
  }

  /// `tick(level)` (`MultiMiningServerManager.java:164`).
  Future<MultiMiningTickResult> tick(MultiMiningLevel level, math.Random random) async {
    if (timeoutTicks++ > maxTimeout) {
      _cleanData();
      return MultiMiningTickResult.stop;
    }

    suppliers.removeWhere((supplier) => !supplier.isActive);
    if (suppliers.isEmpty) {
      _cleanData();
      return MultiMiningTickResult.stop;
    }

    lastKnownSupplierPosition = suppliers.first.location;

    final state = level.blockKeyAt(breakingPos);
    if (!level.isBreakableAt(breakingPos)) {
      _cleanData();
      return MultiMiningTickResult.stop;
    }

    if (timeoutTicks < 5) {
      final hardness = level.hardnessAt(breakingPos);
      var averageMiningSpeed = 0.0;
      for (final supplier in suppliers) {
        averageMiningSpeed += supplier.breakingSpeed(breakingPos, state).abs() / suppliers.length;
      }

      final nextProgressStep = averageMiningSpeed / hardness;
      destroyProgress = destroyProgress + nextProgressStep;

      if (destroyProgress >= 10) {
        // `Collections.shuffle(suppliers)`: the order a drop is offered in is random.
        suppliers.shuffle(random);
        await _dropDrops(level);
        _cleanData();
        return MultiMiningTickResult.broken;
      }
    }

    return MultiMiningTickResult.continueTicking;
  }

  /// `BlockHelper.destroyBlock` with the supplier callback
  /// (`MultiMiningServerManager.java:196-207`).
  Future<void> _dropDrops(MultiMiningLevel level) async {
    for (final drop in await level.destroyBlock(breakingPos)) {
      var remaining = drop.count;
      for (final supplier in suppliers) {
        if (remaining <= 0) break;
        remaining -= supplier.acceptItem(drop.itemKey, remaining);
      }
      if (remaining > 0) {
        await level.popResource(breakingPos, MinedDrop(drop.itemKey, remaining));
      }
    }
  }

  void _cleanData() => suppliers.clear();
}

/// The manager of one level (`MultiMiningServerManager`).
final class MultiMiningServerManager {
  /// The breaking id synced to the client, derived from Create's breaker ids so
  /// the two never collide (`MultiMiningServerManager.java:33-38`).
  final int breakingId;

  /// The seedable source of the supplier shuffle.
  final math.Random random;

  final Map<Pos, BlockBreakingData> _breakingDataMap = {};

  /// One packet per supplier position with the entries that changed.
  final Map<Pos, MultiMiningSyncPacket> _dirtyBreakingData = {};

  /// [breakerIds] is Create's `NEXT_BREAKER_ID` counter: the manager takes the
  /// next value and negates it (`MultiMiningServerManager.java:33-38`).
  MultiMiningServerManager(int Function() breakerIds, {math.Random? random})
    : breakingId = -breakerIds(),
      random = random ?? math.Random();

  /// The live breaking data, for the tests and the counters.
  Map<Pos, BlockBreakingData> get breakingData => Map.unmodifiable(_breakingDataMap);

  /// `addOrRefreshPos` (`MultiMiningServerManager.java:46`): whether [pos] was
  /// newly added.
  bool addOrRefreshPos(Pos pos, MultiMiningSupplier supplier) {
    var data = _breakingDataMap[pos];
    if (data == null) {
      data = BlockBreakingData(pos);
      _breakingDataMap[pos] = data;
      data.addSupplier(supplier, refreshTimeout: true);
      return true;
    }
    data.addSupplier(supplier, refreshTimeout: true);
    return false;
  }

  /// `tick(level)` (`MultiMiningServerManager.java:59,85`): advances every
  /// position once and returns the packets to send this tick, one per supplier
  /// position, in the order the positions were first marked dirty.
  Future<List<MultiMiningSyncPacket>> tick(MultiMiningLevel level) async {
    final keys = _breakingDataMap.keys.toList();
    for (final pos in keys) {
      final data = _breakingDataMap[pos];
      if (data == null) continue;

      final beforeProgress = data.destroyProgressByte;
      final result = await data.tick(level, random);
      switch (result) {
        case MultiMiningTickResult.broken:
          _breakingDataMap.remove(pos);
        case MultiMiningTickResult.stop:
          data.destroyProgress = -1;
          _addSyncingData(data);
          _breakingDataMap.remove(pos);
        case MultiMiningTickResult.continueTicking:
          if (beforeProgress != data.destroyProgressByte) _addSyncingData(data);
      }
    }

    if (_dirtyBreakingData.isEmpty) return const [];
    final packets = _dirtyBreakingData.values.toList();
    _dirtyBreakingData.clear();
    return packets;
  }

  /// Drops everything (`MultiMiningServerManager` is level-attached; the port
  /// keeps it next to the world it belongs to).
  void clear() {
    _breakingDataMap.clear();
    _dirtyBreakingData.clear();
  }

  void _addSyncingData(BlockBreakingData data) {
    final supplierPos = data.lastKnownSupplierPosition;
    if (supplierPos == null) return;
    final packet = _dirtyBreakingData[supplierPos] ??= MultiMiningSyncPacket.serverOutbound(breakingId);
    packet.add(data.breakingPos, data.destroyProgress);
  }
}