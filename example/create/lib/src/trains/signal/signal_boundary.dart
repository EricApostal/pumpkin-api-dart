// `SignalBoundary` (pure): a signal on an edge. It separates two signal edge groups, one per side
// (the "primary" side is the second node of its edge location), and holds the signal block entities
// of each side with their state.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/data.dart';
import '../../common/pos.dart';
import '../../conveyance/nbt_names.dart' show enumFromNbtName;
import '../graph/dimension_palette.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../manager/create.dart';
import '../util/ctag.dart';
import 'signal_propagator.dart';
import 'signal_types.dart';
import 'track_edge_point.dart';

class SignalBoundary extends TrackEdgePoint {
  late Couple<Map<Pos, bool>> blockEntities;
  late Couple<SignalType> types;
  late Couple<String?> groups;
  late Couple<bool> sidesToUpdate;
  late Couple<SignalState> cachedStates;

  late Couple<Map<String, bool>?> chainedSignals;

  SignalBoundary() {
    blockEntities = Couple.fromFactory(() => <Pos, bool>{});
    chainedSignals = Couple<Map<String, bool>?>(null, null);
    groups = Couple<String?>(null, null);
    sidesToUpdate = Couple.create(true, true);
    types = Couple.fromFactory(() => SignalType.ENTRY_SIGNAL);
    cachedStates = Couple.fromFactory(() => SignalState.INVALID);
  }

  void setGroup(bool primary, String? groupId) {
    final previous = groups.get(primary);

    groups.set(primary, groupId);

    final opposite = groups.get(!primary);
    final signalEdgeGroups = Create.RAILWAYS.signalEdgeGroups;

    if (opposite != null && signalEdgeGroups.containsKey(opposite)) {
      final oppositeGroup = signalEdgeGroups[opposite]!;
      if (previous != null) oppositeGroup.removeAdjacent(previous);
      if (groupId != null) oppositeGroup.putAdjacent(groupId);
    }

    if (groupId != null && signalEdgeGroups.containsKey(groupId)) {
      final group = signalEdgeGroups[groupId]!;
      if (opposite != null) group.putAdjacent(opposite);
    }
  }

  void setGroupAndUpdate(TrackNode side, String? groupId) {
    final primary = isPrimary(side);
    setGroup(primary, groupId);
    sidesToUpdate.set(primary, false);
    chainedSignals.set(primary, null);
  }

  @override
  bool canMerge() => true;

  @override
  void invalidate(Object? level) {
    for (final side in blockEntities.toList()) {
      for (final p in side.keys.toList()) {
        invalidateAt(level, _worldIdOf(p), p);
      }
    }
    groups.forEach((uuid) {
      if (uuid != null && Create.RAILWAYS.signalEdgeGroups.remove(uuid) != null) {
        Create.RAILWAYS.sync.edgeGroupRemoved(uuid);
      }
    });
  }

  /// The signals of a boundary live in the world of the edge.
  String _worldIdOf(Pos p) => edgeLocation.getFirst().dimension;

  @override
  bool canCoexistWith(EdgePointType<TrackEdgePoint> otherType, bool front) => otherType == getType();

  @override
  void blockEntityAdded(Object blockEntity, bool front) {
    final info = EdgePointHooks.describe(blockEntity);
    final blockEntitiesOnSide = blockEntities.get(front);
    if (blockEntitiesOnSide.isEmpty) {
      final type = SignalType.bySerializedName(info.properties['type']);
      if (type != null) types.set(front, type);
    }
    blockEntitiesOnSide[info.pos] = EdgePointHooks.reportedPower(blockEntity);
  }

  /// `updateBlockEntityPower(blockEntity)`: the signal block entity at [pos] reports [reportedPower].
  void updateBlockEntityPower(Pos pos, bool reportedPower) {
    for (final front in Iterate.trueAndFalse) {
      final map = blockEntities.get(front);
      if (map.containsKey(pos)) map[pos] = reportedPower;
    }
  }

  @override
  void blockEntityRemoved(Pos blockEntityPos, bool front) {
    blockEntities.forEach((s) => s.remove(blockEntityPos));
    if (blockEntities.both((m) => m.isEmpty)) removeFromAllGraphs();
  }

  @override
  void onRemoved(TrackGraph graph) {
    super.onRemoved(graph);
    SignalPropagator.onSignalRemoved(graph, this);
  }

  void queueUpdate(TrackNode side) {
    sidesToUpdate.set(isPrimary(side), true);
  }

  String? getGroup(TrackNode side) => groups.get(isPrimary(side));

  @override
  bool canNavigateVia(TrackNode side) => blockEntities.get(isPrimary(side)).isNotEmpty;

  OverlayState getOverlayFor(Pos blockEntity) {
    for (final first in Iterate.trueAndFalse) {
      final set = blockEntities.get(first);
      for (final blockPos in set.keys) {
        // Java returns after looking at the first position of the first non-empty side
        if (blockPos == blockEntity) return blockEntities.get(!first).isEmpty ? OverlayState.RENDER : OverlayState.DUAL;
        return OverlayState.SKIP;
      }
    }
    return OverlayState.SKIP;
  }

  SignalType getTypeFor(Pos blockEntity) => types.get(blockEntities.getFirst().containsKey(blockEntity));

  SignalState getStateFor(Pos blockEntity) {
    for (final first in Iterate.trueAndFalse) {
      final set = blockEntities.get(first);
      if (set.containsKey(blockEntity)) return cachedStates.get(first);
    }
    return SignalState.INVALID;
  }

  @override
  void tick(TrackGraph graph, bool preTrains) {
    super.tick(graph, preTrains);
    if (!preTrains) {
      _tickState(graph);
      return;
    }
    for (final front in Iterate.trueAndFalse) {
      if (!sidesToUpdate.get(front)) continue;
      sidesToUpdate.set(front, false);
      SignalPropagator.propagateSignalGroup(graph, this, front);
      chainedSignals.set(front, null);
    }
  }

  void _tickState(TrackGraph graph) {
    for (final current in Iterate.trueAndFalse) {
      final set = blockEntities.get(current);
      if (set.isEmpty) continue;

      final forcedRed = isForcedRedPrimary(current);
      final group = groups.get(current);
      if (group == groups.get(!current)) {
        cachedStates.set(current, SignalState.INVALID);
        continue;
      }

      final signalEdgeGroups = Create.RAILWAYS.signalEdgeGroups;
      final signalEdgeGroup = signalEdgeGroups[group];
      if (signalEdgeGroup == null) {
        cachedStates.set(current, SignalState.INVALID);
        continue;
      }

      final occupiedUnlessBySelf = forcedRed || signalEdgeGroup.isOccupiedUnless(this);
      cachedStates.set(current, occupiedUnlessBySelf ? SignalState.RED : _resolveSignalChain(graph, current));
    }
  }

  /// `isForcedRed(TrackNode side)`.
  bool isForcedRed(TrackNode side) => isForcedRedPrimary(isPrimary(side));

  /// `isForcedRed(boolean primary)`.
  bool isForcedRedPrimary(bool primary) {
    for (final b in blockEntities.get(primary).values) {
      if (b) return true;
    }
    return false;
  }

  SignalState _resolveSignalChain(TrackGraph graph, bool side) {
    if (types.get(side) != SignalType.CROSS_SIGNAL) return SignalState.GREEN;

    if (chainedSignals.get(side) == null) {
      chainedSignals.set(side, SignalPropagator.collectChainedSignals(graph, this, side));
    }

    var allPathsFree = true;
    var noPathsFree = true;
    var invalid = false;

    for (final entry in chainedSignals.get(side)!.entries) {
      final uuid = entry.key;
      final sideOfOther = entry.value;
      final otherSignal = graph.getPoint(EdgePointType.SIGNAL, uuid);
      if (otherSignal == null) {
        invalid = true;
        break;
      }
      if (otherSignal.blockEntities.get(sideOfOther).isEmpty) continue;
      final otherState = otherSignal.cachedStates.get(sideOfOther);
      allPathsFree &= otherState == SignalState.GREEN || otherState == SignalState.INVALID;
      noPathsFree &= otherState == SignalState.RED;
    }
    if (invalid) {
      chainedSignals.set(side, null);
      return SignalState.INVALID;
    }
    if (allPathsFree) return SignalState.GREEN;
    if (noPathsFree) return SignalState.RED;
    return SignalState.YELLOW;
  }

  @override
  void read(CTag nbt, bool migration, DimensionPalette dimensions) {
    super.read(nbt, migration, dimensions);

    if (migration) return;

    blockEntities = Couple.fromFactory(() => <Pos, bool>{});
    groups = Couple<String?>(null, null);

    for (var i = 1; i <= 2; i++) {
      if (nbt.contains('Tiles$i')) {
        final first = i == 1;
        for (final c in nbt.getCompoundList('Tiles$i')) {
          blockEntities.get(first)[c.getBlockPos('Pos')] = c.getBoolean('Power');
        }
      }
    }

    for (var i = 1; i <= 2; i++) {
      if (nbt.contains('Group$i')) groups.set(i == 1, nbt.getUuid('Group$i'));
    }
    for (var i = 1; i <= 2; i++) {
      sidesToUpdate.set(i == 1, nbt.contains('Update$i'));
    }
    for (var i = 1; i <= 2; i++) {
      types.set(i == 1, enumFromNbtName(nbt.getString('Type$i'), SignalType.values));
    }
    for (var i = 1; i <= 2; i++) {
      cachedStates.set(i == 1, enumFromNbtName(nbt.getString('State$i'), SignalState.values));
    }
  }

  @override
  void readBuffer(PacketReader buffer, DimensionPalette dimensions) {
    super.readBuffer(buffer, dimensions);
    for (var i = 1; i <= 2; i++) {
      if (buffer.readBool()) groups.set(i == 1, buffer.readUuid());
    }
  }

  @override
  void write(CTag nbt, DimensionPalette dimensions) {
    super.write(nbt, dimensions);
    for (var i = 1; i <= 2; i++) {
      final side = blockEntities.get(i == 1);
      if (side.isNotEmpty) {
        nbt.putCompoundList('Tiles$i', [
          for (final e in side.entries)
            CTag()
              ..putBlockPos('Pos', e.key)
              ..putBoolean('Power', e.value),
        ]);
      }
    }
    for (var i = 1; i <= 2; i++) {
      final g = groups.get(i == 1);
      if (g != null) nbt.putUuid('Group$i', g);
    }
    for (var i = 1; i <= 2; i++) {
      if (sidesToUpdate.get(i == 1)) nbt.putBoolean('Update$i', true);
    }
    for (var i = 1; i <= 2; i++) {
      nbt.putString('Type$i', types.get(i == 1).name);
    }
    for (var i = 1; i <= 2; i++) {
      nbt.putString('State$i', cachedStates.get(i == 1).name);
    }
  }

  @override
  void writeBuffer(PacketWriter buffer, DimensionPalette dimensions) {
    super.writeBuffer(buffer, dimensions);
    for (var i = 1; i <= 2; i++) {
      final g = groups.get(i == 1);
      buffer.writeBool(g != null);
      if (g != null) buffer.writeUuid(g);
    }
  }

  void cycleSignalType(Pos pos) {
    final all = SignalType.values;
    types.set(blockEntities.getFirst().containsKey(pos), all[(getTypeFor(pos).index + 1) % all.length]);
  }
}
