// `ChainConveyorBlockEntity` (host side): the connections between chain conveyors, the routing
// table that advertises package ports, and the packages travelling along a connection or looping
// around a conveyor. Ported from
// `content/kinetics/chainConveyor/ChainConveyorBlockEntity.java` (the client-only box visuals and
// render bounds are omitted).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/kinetics.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../items/item_codec.dart';
import '../items/item_data.dart';
import '../runtime.dart';
import 'chain_conveyor_logic.dart';
import 'chain_conveyor_port.dart';
import 'chain_conveyor_routing.dart';

/// `ChainConveyorBlockEntity`.
class ChainConveyorBlockEntity extends KineticBlockEntity {
  ChainConveyorBlockEntity(super.worldId, super.pos);

  /// `connections`: the other conveyors this one is chained to, as local offsets.
  final Set<Pos> connections = {};

  /// `connectionStats`, rebuilt when the direction changes or a connection is added.
  Map<Pos, ConnectionStats>? connectionStats;

  /// `loopPorts`: package ports on the loop, by the port's local offset (negated).
  final Map<Pos, ConnectedPort> loopPorts = {};

  /// `travelPorts`: package ports on a connection.
  final Map<Pos, ConnectedPort> travelPorts = {};

  final ChainConveyorRoutingTable routingTable = ChainConveyorRoutingTable();

  final List<ChainConveyorPackage> loopingPackages = [];
  final Map<Pos, List<ChainConveyorPackage>> travellingPackages = {};

  bool reversed = false;

  /// Set by the block: the chains are not dropped when the conveyor is broken in creative.
  bool cancelDrops = false;

  /// Whether the connections must be validated against the neighbours.
  bool checkInvalid = true;

  Pos? chainDestroyedEffectToSend;

  Pos get p => this.pos.toPos();

  /// The capacity of the conveyor (`logistics.chainConveyorCapacity`).
  int get _capacity =>
      ConveyanceRuntime.loaded ? ConveyanceRuntime.i.chainConveyorCapacity : 20;

  bool get canAcceptMorePackages =>
      loopingPackages.length + travellingPackages.length < _capacity;

  bool canAcceptPackagesFor(Pos? connection) {
    if (connection == null && !canAcceptMorePackages) return false;
    if (connection != null) {
      final other = store.typed<ChainConveyorBlockEntity>(
        worldId,
        (p + connection).toBlockPos(),
      );
      if (other == null || !other.canAcceptMorePackages) return false;
    }
    return true;
  }

  bool get canAcceptMorePackagesFromOtherConveyor =>
      loopingPackages.length < _capacity;

  // -- Kinetic hooks --------------------------------------------------------------------------

  @override
  List<KPos> addPropagationLocations(
    KineticBlockDef block,
    KState state,
    List<KPos> neighbours,
  ) {
    for (final c in connections) {
      neighbours.add(KPos(p.x + c.x, p.y + c.y, p.z + c.z));
    }
    return super.addPropagationLocations(block, state, neighbours);
  }

  @override
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  ) {
    if (connections.contains((
      target.kpos.x - p.x,
      target.kpos.y - p.y,
      target.kpos.z - p.z,
    ))) {
      if (target is! ChainConveyorBlockEntity) return 0;
      return 1;
    }
    return super.propagateRotationTo(
      target,
      stateFrom,
      stateTo,
      diff,
      connectedViaAxes,
      connectedViaCogs,
    );
  }

  // -- Lifecycle ------------------------------------------------------------------------------

  @override
  void lazyTick() {
    super.lazyTick();
    prepareStats();
  }

  @override
  void tick() {
    super.tick();

    if (checkInvalid && world != null) {
      checkInvalid = false;
      removeInvalidConnections();
    }

    final s = speed / 360;
    final distancePerTick = s.abs();
    final degreesPerTick = (s / (math.pi * 1.5)) * 360;
    final reversedPreviously = reversed;

    prepareStats();

    if (world == null) return;

    routingTable.tick();
    if (routingTable.shouldAdvertise()) {
      for (final connection in connections) {
        final other = store.typed<ChainConveyorBlockEntity>(
          worldId,
          (p + connection).toBlockPos(),
        );
        if (other != null)
          routingTable.advertiseTo(connection, other.routingTable);
      }
      routingTable.changed = false;
      routingTable.lastUpdate = 0;
    }

    if (s == 0) {
      updateBoxWorldPositions();
      return;
    }

    if (reversedPreviously != reversed) {
      for (final entry in travellingPackages.entries.toList()) {
        final offset = entry.key;
        final other = store.typed<ChainConveyorBlockEntity>(
          worldId,
          (p + offset).toBlockPos(),
        );
        if (other == null) continue;
        for (final box in List.of(entry.value)) {
          if (box.justFlipped) continue;
          box.justFlipped = true;
          final length =
              math.sqrt(
                offset.x * offset.x + offset.y * offset.y + offset.z * offset.z,
              ) -
              22 / 16;
          box.chainPosition = length - box.chainPosition;
          other.addTravellingPackage(box, -offset);
          entry.value.remove(box);
        }
      }
      notifyUpdate();
    }

    // Travelling packages.
    for (final entry in travellingPackages.entries) {
      final target = entry.key;
      final stats = connectionStats?[target];
      if (stats == null) continue;

      for (final box in List.of(entry.value)) {
        box.justFlipped = false;

        final prevChainPosition = box.chainPosition;
        box.chainPosition = math.min(
          stats.chainLength,
          box.chainPosition + distancePerTick,
        );

        var anticipatePosition = box.chainPosition + distancePerTick * 4;
        anticipatePosition = math.min(stats.chainLength, anticipatePosition);

        var removed = false;
        for (final portEntry in travelPorts.entries) {
          final port = portEntry.value;
          final chainPosition = port.chainPosition;

          if (prevChainPosition > chainPosition) continue;
          if (target != port.connection) continue;

          final notAtPositionYet = box.chainPosition < chainPosition;
          if (notAtPositionYet && anticipatePosition < chainPosition) continue;
          if (!matchPackage(box.item, port.filter)) continue;
          if (notAtPositionYet) {
            notifyPortToAnticipate(portEntry.key);
            continue;
          }

          if (!exportToPort(box, portEntry.key)) continue;

          entry.value.remove(box);
          notifyUpdate();
          removed = true;
          break;
        }
        if (removed) continue;

        if (box.chainPosition < stats.chainLength) continue;

        // Transfer to the other conveyor.
        final other = store.typed<ChainConveyorBlockEntity>(
          worldId,
          (p + target).toBlockPos(),
        );
        if (other != null) {
          box.chainPosition = wrapAngle(
            stats.tangentAngle + 180 + 2 * 35 * (reversed ? -1 : 1),
          );
          other.addLoopingPackage(box);
          entry.value.remove(box);
          notifyUpdate();
        }
      }
    }

    // Looping packages.
    for (final box in List.of(loopingPackages)) {
      box.justFlipped = false;

      final prevChainPosition = box.chainPosition;
      box.chainPosition = wrapAngle(box.chainPosition + degreesPerTick);

      var anticipatePosition = wrapAngle(
        box.chainPosition + degreesPerTick * 4,
      );

      var removed = false;
      for (final portEntry in loopPorts.entries) {
        final port = portEntry.value;
        final offBranchAngle = port.chainPosition;

        final notAtPositionYet = !loopThresholdCrossed(
          box.chainPosition,
          prevChainPosition,
          offBranchAngle,
          reversed: reversed,
        );
        if (notAtPositionYet &&
            !loopThresholdCrossed(
              anticipatePosition,
              prevChainPosition,
              offBranchAngle,
              reversed: reversed,
            )) {
          continue;
        }
        if (!matchPackage(box.item, port.filter)) continue;
        if (notAtPositionYet) {
          notifyPortToAnticipate(portEntry.key);
          continue;
        }

        if (!exportToPort(box, portEntry.key)) continue;

        loopingPackages.remove(box);
        notifyUpdate();
        removed = true;
        break;
      }
      if (removed) continue;

      for (final connection in connections) {
        final other = store.typed<ChainConveyorBlockEntity>(
          worldId,
          (p + connection).toBlockPos(),
        );
        if (other != null && !other.canAcceptMorePackagesFromOtherConveyor)
          continue;

        final stats = connectionStats?[connection];
        if (stats == null) continue;
        final offBranchAngle = stats.tangentAngle;

        if (!loopThresholdCrossed(
          box.chainPosition,
          prevChainPosition,
          offBranchAngle,
          reversed: reversed,
        )) {
          continue;
        }
        if (routingTable.getExitFor(box.item) != connection) continue;

        box.chainPosition = 0;
        addTravellingPackage(box, connection);
        loopingPackages.remove(box);
        removed = true;
        break;
      }
    }

    updateBoxWorldPositions();
  }

  @override
  void onRemoved() {
    for (final connection in connections) {
      chainDestroyed(connection, !cancelDrops, false);
      final other = store.typed<ChainConveyorBlockEntity>(
        worldId,
        (p + connection).toBlockPos(),
      );
      other?.removeConnectionTo(p);
    }
    for (final box in loopingPackages) {
      _drop(box);
    }
    for (final list in travellingPackages.values) {
      for (final box in list) {
        _drop(box);
      }
    }
    super.onRemoved();
  }

  // -- Connections ----------------------------------------------------------------------------

  void removeInvalidConnections() {
    var changed = false;
    for (final next in List.of(connections)) {
      final target = p + next;
      if (!(world?.isLoaded(pos: target.toBlockPos()) ?? false)) continue;
      final other = store.typed<ChainConveyorBlockEntity>(
        worldId,
        target.toBlockPos(),
      );
      if (other != null && other.connections.contains(-next)) continue;
      connections.remove(next);
      changed = true;
    }
    if (changed) notifyUpdate();
  }

  void notifyConnectedToValidate() {
    for (final connection in connections) {
      final target = p + connection;
      if (!(world?.isLoaded(pos: target.toBlockPos()) ?? false)) continue;
      store
              .typed<ChainConveyorBlockEntity>(worldId, target.toBlockPos())
              ?.checkInvalid =
          true;
    }
  }

  bool addConnectionTo(Pos target) {
    final local = target - p;
    final added = connections.add(local);
    if (added) {
      notifyUpdate();
      prepareStats();
    }
    detachKinetics();
    updateSpeed = true;
    return added;
  }

  bool removeConnectionTo(Pos target) {
    final local = target - p;
    if (!connections.contains(local)) return false;
    detachKinetics();
    connections.remove(local);
    connectionStats?.remove(local);
    final packages = travellingPackages.remove(local);
    if (packages != null) {
      for (final box in packages) {
        _drop(box);
      }
    }
    notifyUpdate();
    updateSpeed = true;
    return true;
  }

  void chainDestroyed(Pos target, bool spawnDrops, bool sendEffect) {
    final chainCount = getChainCost(target);
    if (sendEffect) {
      chainDestroyedEffectToSend = target;
      sendData();
    }
    if (!spawnDrops) return;

    prepareStats();
    final w = world;
    if (w == null) return;
    final spawned = forPointsAlongChains(
      p,
      target,
      chainCount,
      connectionStats ?? {},
      (vec) {
        final stack = ItemStack.create(
          registryKey: 'minecraft:iron_chain',
          count: 1,
        );
        unawaited(w.dropItem(vec, stack));
      },
    );
    if (!spawned) {
      var left = chainCount;
      while (left > 0) {
        final count = math.min(left, 64);
        final stack = ItemStack.create(
          registryKey: 'minecraft:iron_chain',
          count: count,
        );
        unawaited(w.dropItem(p.center, stack));
        left -= 64;
      }
    }
  }

  /// `getChainsFromInventory(player, chain, cost, simulate)`.
  Future<bool> getChainsFromInventory(
    Player player,
    String chainKey,
    int cost, {
    bool simulate = false,
  }) async {
    final inventory = player.getInventory().storage;
    var found = 0;
    for (var slot = 0; slot < inventory.getSize() && found < cost; slot++) {
      final stack = inventory.getItem(slot: slot);
      if (stack == null) continue;
      final String key;
      final int count;
      try {
        key = await stack.getRegistryKey();
        count = await stack.getCount();
      } on Object {
        continue;
      }
      if (key != chainKey || count <= 0) continue;
      final take = math.min(cost - found, count);
      if (!simulate) {
        final left = count - take;
        if (left <= 0) {
          await inventory.setItem(slot: slot, item: null);
        } else {
          await stack.setCount(count: left);
        }
      }
      found += take;
    }

    // The offhand counts as well.
    if (found < cost) {
      final off = player.getInventory().getItemInHand(hand: Hand.left);
      if (off != null) {
        try {
          final key = await off.getRegistryKey();
          final count = await off.getCount();
          if (key == chainKey && count > 0) {
            final take = math.min(cost - found, count);
            if (!simulate) {
              final left = count - take;
              await off.setCount(count: left);
            }
            found += take;
          }
        } on Object {
          // an unreadable stack is skipped
        }
      }
    }

    return found >= cost;
  }

  // -- Package movement -----------------------------------------------------------------------

  void prepareStats() {
    final s = speed;
    if (reversed != s < 0 && s != 0) {
      reversed = s < 0;
      connectionStats = null;
    }
    if (connectionStats == null) {
      connectionStats = {};
      for (final c in connections) {
        connectionStats![c] = calculateConnectionStats(
          p,
          c,
          reversed: reversed,
        );
      }
    }
  }

  void updateBoxWorldPositions() {
    prepareStats();
    for (final entry in travellingPackages.entries) {
      final stats = connectionStats?[entry.key];
      if (stats == null) continue;
      for (final box in entry.value) {
        box.worldPosition = getPackagePosition(box.chainPosition, entry.key);
      }
    }
    for (final box in loopingPackages) {
      box.worldPosition = getPackagePosition(box.chainPosition, null);
      box.yaw = wrapAngle(box.chainPosition);
      if (reversed) box.yaw += 180;
    }
  }

  Vec3 getPackagePosition(double chainPosition, Pos? travelTarget) =>
      chainPackagePosition(
        p,
        chainPosition,
        travelTarget,
        connectionStats ?? {},
      );

  bool addTravellingPackage(ChainConveyorPackage box, Pos connection) {
    if (!connections.contains(connection)) return false;
    travellingPackages.putIfAbsent(connection, () => []).add(box);
    notifyUpdate();
    return true;
  }

  bool addLoopingPackage(ChainConveyorPackage box) {
    loopingPackages.add(box);
    notifyUpdate();
    return true;
  }

  bool exportToPort(ChainConveyorPackage box, Pos offset) {
    final port = _portAt(p + offset);
    if (port == null) return false;
    if (port.isAnimationInProgress) return false;
    if (port.isBackedUp) return false;
    port.startAnimation(box.item);
    return true;
  }

  void notifyPortToAnticipate(Pos offset) {
    _portAt(p + offset)?.sendAnticipate();
  }

  ChainConveyorPort? _portAt(Pos at) {
    final be = store.at(worldId, at.toBlockPos());
    if (be is ChainConveyorPort) return be as ChainConveyorPort;
    return ConveyanceRuntime.loaded
        ? ConveyanceRuntime.i.chainPorts.at(worldId, at)
        : null;
  }

  /// `PackagePortTarget.ChainConveyorFrogportTarget`: a port registers itself on the conveyor.
  void receivePortInfo(
    Pos portOffset,
    double chainPosition,
    Pos? connection,
    String filter,
  ) {
    routingTable.receivePortInfo(filter, connection ?? posZero);
    (connection == null ? loopPorts : travelPorts)[portOffset] = ConnectedPort(
      chainPosition,
      connection,
      filter,
    );
  }

  /// The port at [portOffset] was removed.
  void removePort(Pos portOffset) {
    loopPorts.remove(portOffset);
    travelPorts.remove(portOffset);
  }

  void notifyUpdate() {
    markDirty();
    sendData();
  }

  void _drop(ChainConveyorPackage box) {
    final at = box.worldPosition;
    final w = world;
    if (w == null || at == null) return;
    unawaited(ItemCodec.drop(w, (at.$1, at.$2 - .5, at.$3), box.item));
  }

  // -- NBT ------------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);

    final effect = chainDestroyedEffectToSend;
    if (clientPacket && effect != null) {
      NbtHelper.writeBlockPos(tag, 'DestroyEffect', effect);
      chainDestroyedEffectToSend = null;
    }

    tag.putList('Connections', [
      for (final c in connections) NbtTagIntArray([c.x, c.y, c.z]),
    ]);
    tag.putList('TravellingPackages', [
      for (final entry in travellingPackages.entries)
        NbtCompound()
          ..putIntArray('Target', [entry.key.x, entry.key.y, entry.key.z])
          ..putList('Packages', [
            for (final p in entry.value)
              _packageNbt(p, clientPacket: clientPacket),
          ]),
    ]);
    tag.putList('LoopingPackages', [
      for (final p in loopingPackages)
        _packageNbt(p, clientPacket: clientPacket),
    ]);
  }

  NbtCompound _packageNbt(
    ChainConveyorPackage box, {
    required bool clientPacket,
  }) {
    final nbt = NbtCompound()
      ..putFloat('Position', box.chainPosition)
      ..putCompound(
        'Item',
        ItemCodec.toTag(box.item, clientPacket: clientPacket),
      );
    if (clientPacket) nbt.putInt('NetID', box.netId);
    return nbt;
  }

  ChainConveyorPackage _readPackage(NbtCompound nbt) {
    final position = nbt.getDouble('Position') ?? 0;
    final item = ItemCodec.fromAnyNbt(nbt.getCompound('Item'));
    final netId = nbt.getInt('NetID');
    return ChainConveyorPackage(
      position,
      item,
      netId ?? ChainConveyorPackage.nextNetId(),
    );
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);

    connections.clear();
    for (final e in tag.getList('Connections') ?? const <Object>[]) {
      if (e is NbtTagIntArray && e.value.length >= 3) {
        connections.add((e.value[0], e.value[1], e.value[2]));
      }
    }

    travellingPackages.clear();
    for (final e in tag.getList('TravellingPackages') ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final target = NbtHelper.readBlockPos(e, 'Target');
      travellingPackages[target] = [
        for (final p in e.getList('Packages') ?? const <Object>[])
          if (p is NbtCompound) _readPackage(p),
      ];
    }

    loopingPackages
      ..clear()
      ..addAll([
        for (final e in tag.getList('LoopingPackages') ?? const <Object>[])
          if (e is NbtCompound) _readPackage(e),
      ]);

    connectionStats = null;
    updateBoxWorldPositions();
  }
}
