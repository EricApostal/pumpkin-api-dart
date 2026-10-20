// `BeltTunnelBlockEntity` and `BrassTunnelBlockEntity` (server behaviour): the tunnel's sides and
// flaps, and the brass tunnel's distribution of the items it takes off the belt (split, round
// robin, forced modes, randomize, prefer nearest and synchronize) with the per-side filters.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/kinetics.dart' show ScrollValueBehaviour;
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../behaviours/filtering.dart';
import '../../behaviours/processing_bridge.dart';
import '../../behaviours/value_box.dart';
import '../../belt/belt_ports.dart';
import '../../belt/transported_item.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../nbt_names.dart';
import '../../runtime.dart';
import '../transport_inventory.dart';
import '../transport_inventory_api.dart';
import '../transport_support.dart';

/// `BrassTunnelBlockEntity.SelectionMode`.
enum TunnelSelectionMode {
  split,
  forcedSplit,
  roundRobin,
  forcedRoundRobin,
  preferNearest,
  randomize,
  synchronize,
}

/// `BeltTunnelBlockEntity`.
class BeltTunnelBlockEntity extends CreateBlockEntity
    implements BeltTunnelPort, ItemInventoryProvider {
  /// The faces with a flap (a visible, non-occluded output).
  final Set<Direction> flaps = {};

  /// The faces the tunnel connects to (for the filters).
  final Set<Direction> sides = {};

  BeltTunnelBlockEntity(super.worldId, super.pos);

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  BState get state => rt.stateAt(worldId, this.pos.toPos());

  BState stateAt(Pos p) => rt.stateAt(worldId, p);

  // -- BeltTunnelPort --------------------------------------------------------------------------

  @override
  Pos get position => this.pos.toPos();

  @override
  bool get isBrass => false;

  @override
  bool get hasDistributionBehaviour => false;

  @override
  bool get canTakeItems => true;

  @override
  bool canInsert(Direction side, ItemValue stack) => true;

  @override
  void setStackToDistribute(ItemValue stack, Direction? enteredFrom) {}

  @override
  bool get isAndesiteJunction => !isBrass && isJunctionTunnel(state);

  @override
  Axis get horizontalAxis => state.axisOf('axis') ?? Axis.x;

  @override
  bool hasFlap(Direction side) => flaps.contains(side);

  @override
  void flap(Direction side, bool inward) {
    // The flap animation is a client packet (`TunnelFlapPacket`); out of scope.
  }

  @override
  void itemReceived(int amount) {
    // `AccumulatedItemCountDisplaySource`; only the display link reads it.
  }

  // -- ItemInventoryProvider -------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) =>
      ItemInventories.at(worldId, this.pos.toPos().below);

  // -- Lifecycle -------------------------------------------------------------------------------

  @override
  void initialize() {
    super.initialize();
    updateTunnelConnections();
  }

  /// `updateTunnelConnections`.
  void updateTunnelConnections() {
    flaps.clear();
    sides.clear();
    final tunnelState = state;
    final axis = tunnelState.axisOf('axis') ?? Axis.x;
    for (final direction in Direction.planeHorizontal) {
      if (direction.axis != axis) {
        final positive =
            (direction.axisDirection == AxisDirection.positive) ^
            (direction.axis == Axis.z);
        final shape = tunnelState['shape'];
        if (isStraightTunnel(tunnelState)) continue;
        if (positive && shape == 't_left') continue;
        if (!positive && shape == 't_right') continue;
      }
      sides.add(direction);

      final nextState = stateAt(this.pos.toPos().relative(direction));
      if (isTunnelState(nextState)) continue;
      if (isBeltFunnelState(nextState) &&
          nextState['shape'] == 'extended' &&
          nextState.dir('facing') == direction.opposite) {
        continue;
      }
      flaps.add(direction);
    }
    sendData();
  }

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    // Java's `writeFlapsAndSides` writes `ListTag`s of `IntTag`, not int arrays.
    tag
      ..putList('Flaps', [for (final v in directionValues(flaps)) NbtTagInt(v)])
      ..putList('Sides', [
        for (final v in directionValues(sides)) NbtTagInt(v),
      ]);
  }

  /// Reads `Sides` (and `Flaps`) before the behaviours are read, so the brass tunnel's sided
  /// filters exist when their NBT is loaded.
  void readSides(NbtCompound tag) {
    sides
      ..clear()
      ..addAll(directionsFromValues(_intTags(tag.getList('Sides'))));
    flaps
      ..clear()
      ..addAll(directionsFromValues(_intTags(tag.getList('Flaps'))));
    // Backwards compatibility: `Flaps` without `Sides`.
    if (!tag.containsKey('Sides') && tag.containsKey('Flaps'))
      sides.addAll(flaps);
  }

  /// The values of the `IntTag` elements of [list] (Java's `inbt instanceof IntTag`).
  static Iterable<int> _intTags(List<Object>? list) sync* {
    for (final e in list ?? const <Object>[]) {
      if (e is NbtTagInt) yield e.value;
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    readSides(tag);
    super.read(tag, clientPacket: clientPacket);
  }
}

/// `BrassTunnelBlockEntity`.
class BrassTunnelBlockEntity extends BeltTunnelBlockEntity {
  late final SidedFilteringBehaviour filtering;
  late final ScrollValueBehaviour selectionMode;

  bool connectedLeft = false;
  bool connectedRight = false;

  ItemValue stackToDistribute = ItemValue.empty;
  Direction? stackEnteredFrom;

  double distributionProgress = 0;
  int distributionDistanceLeft = 0;
  int distributionDistanceRight = 0;
  int previousOutputIndex = 0;

  final List<(Pos, Direction)> _targets = [];
  final List<(Pos, Direction)> _filteredTargets = [];

  bool newItemArrived = false;
  bool syncedOutputActive = false;
  final Set<BrassTunnelBlockEntity> syncSet = {};

  late final _BrassTunnelInventory _inventory = _BrassTunnelInventory(this);

  BrassTunnelBlockEntity(super.worldId, super.pos) {
    filtering = addBehaviour(
      SidedFilteringBehaviour(
        const FixedSlot(_filterSlot),
        (side) => sides.contains(side),
      ),
    );
    selectionMode = addBehaviour(
      ScrollValueBehaviour()
        ..between(0, TunnelSelectionMode.values.length - 1)
        ..onlyActiveWhen(() => hasDistributionBehaviour)
        ..withCallback(_onSelectionModeChanged),
    );
  }

  static Vec3 _filterSlot(BState state) => voxel(8, 6, 15.5);

  TunnelSelectionMode get selectionModeValue =>
      TunnelSelectionMode.values[selectionMode.value.clamp(0, 6)];

  @override
  bool get isBrass => true;

  @override
  bool get hasDistributionBehaviour {
    if (flaps.isEmpty) return false;
    if (connectedLeft || connectedRight) return true;
    final axis = state.axisOf('axis') ?? Axis.x;
    for (final direction in flaps) {
      if (direction.axis != axis) return true;
    }
    return false;
  }

  @override
  bool get canTakeItems => stackToDistribute.isEmpty && !syncedOutputActive;

  @override
  bool canInsert(Direction side, ItemValue stack) {
    if (!filtering.testSide(side, stack)) return false;
    if (!hasDistributionBehaviour) return true;
    return stackToDistribute.isEmpty;
  }

  @override
  void setStackToDistribute(ItemValue stack, Direction? enteredFrom) {
    stackToDistribute = stack;
    stackEnteredFrom = enteredFrom;
    distributionProgress = -1;
    if (stack.isNotEmpty) newItemArrived = true;
    markDirty();
    sendData();
  }

  /// `getStackToDistribute`.
  ItemValue getStackToDistribute() => stackToDistribute;

  // -- Inventory -------------------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) => _inventory;

  // -- Tick ------------------------------------------------------------------------------------

  @override
  Future<void> tick() async {
    super.tick();
    final below = rt.beAt(worldId, this.pos.toPos().below);
    if (distributionProgress > 0) distributionProgress--;
    if (below is! BeltEnvironment) return;
    final env = below as BeltEnvironment;
    if (env.speed == 0) return;
    if (stackToDistribute.isEmpty && !syncedOutputActive) return;

    if (distributionProgress == -1) {
      _targets.clear();
      _filteredTargets.clear();
      distributionDistanceLeft = 0;
      distributionDistanceRight = 0;
      syncSet.clear();
      final validOutputs = gatherValidOutputs();
      if (selectionModeValue == TunnelSelectionMode.synchronize) {
        var allEmpty = true;
        var allFull = true;
        for (final be in syncSet) {
          final hasStack = be.stackToDistribute.isNotEmpty;
          allEmpty = allEmpty && !hasStack;
          allFull = allFull && hasStack;
        }
        final notifySyncedOut = !allEmpty;
        if (allFull || allEmpty) {
          for (final be in syncSet) {
            be.syncedOutputActive = notifySyncedOut;
          }
        }
      }
      if (validOutputs == null) return;
      if (stackToDistribute.isEmpty) return;

      for (final pair in validOutputs) {
        final tunnel = pair.$1;
        final output = pair.$2;
        if (await insertIntoTunnel(tunnel, output, stackToDistribute, true) ==
            null)
          continue;
        final filtered = !tunnel.flapFilterEmpty(output);
        (filtered ? _filteredTargets : _targets).add((
          tunnel.pos.toPos(),
          output,
        ));
        final distance = tunnel.pos.x + tunnel.pos.z - this.pos.x - this.pos.z;
        if (distance < 0) {
          distributionDistanceLeft = math.max(
            distributionDistanceLeft,
            -distance,
          );
        } else {
          distributionDistanceRight = math.max(
            distributionDistanceRight,
            distance,
          );
        }
      }

      if (_targets.isEmpty && _filteredTargets.isEmpty) return;

      if (newItemArrived) {
        newItemArrived = false;
        distributionProgress = 2;
      } else {
        if (selectionModeValue != TunnelSelectionMode.synchronize ||
            syncedOutputActive) {
          distributionProgress = rt.brassTunnelTimer.toDouble();
          sendData();
        }
        return;
      }
    }

    if (distributionProgress != 0) return;

    for (final list in [_filteredTargets, _targets]) {
      if (stackToDistribute.isEmpty) break;
      final valid = <(BrassTunnelBlockEntity, Direction)>[];
      for (final (tunnelPos, output) in list) {
        if (tunnelPos == this.pos.toPos() && output == stackEnteredFrom)
          continue;
        final be = rt.beAt(worldId, tunnelPos);
        if (be is! BrassTunnelBlockEntity) continue;
        valid.add((be, output));
      }
      await distribute(valid);
      distributionProgress = -1;
    }
  }

  // -- Distribution ----------------------------------------------------------------------------

  Future<void> distribute(
    List<(BrassTunnelBlockEntity, Direction)> validTargets,
  ) async {
    final amountTargets = validTargets.length;
    if (amountTargets == 0) return;

    final distributed = <(BrassTunnelBlockEntity, Direction), ItemValue>{};
    final full = <(BrassTunnelBlockEntity, Direction)>{};

    var indexStart = previousOutputIndex % amountTargets;
    final mode = selectionModeValue;
    final force =
        mode == TunnelSelectionMode.forcedRoundRobin ||
        mode == TunnelSelectionMode.forcedSplit;
    final split =
        mode == TunnelSelectionMode.forcedSplit ||
        mode == TunnelSelectionMode.split;
    final robin =
        mode == TunnelSelectionMode.forcedRoundRobin ||
        mode == TunnelSelectionMode.roundRobin;

    if (mode == TunnelSelectionMode.randomize)
      indexStart = sharedRandom.nextInt(amountTargets);
    if (mode == TunnelSelectionMode.preferNearest ||
        mode == TunnelSelectionMode.synchronize)
      indexStart = 0;

    var toDistribute = stackToDistribute;
    for (final distributeAgain in [true, false]) {
      var toDistributeThisCycle = toDistribute;
      var remainingOutputs = amountTargets;
      var leftovers = 0;

      for (final simulate in [true, false]) {
        if (remainingOutputs == 0) break;
        leftovers = 0;
        var index = indexStart;
        final stackSize = toDistribute.count;
        final splitStackSize = stackSize ~/ remainingOutputs;
        var splitRemainder = stackSize % remainingOutputs;
        var visited = 0;

        toDistributeThisCycle = toDistribute;
        if (!(force || split) && simulate) continue;

        while (visited < amountTargets) {
          final pair = validTargets[index];
          final tunnel = pair.$1;
          final side = pair.$2;
          index = (index + 1) % amountTargets;
          visited++;

          if (full.contains(pair)) {
            if (split && simulate) remainingOutputs--;
            continue;
          }

          final count = split
              ? splitStackSize + (splitRemainder > 0 ? 1 : 0)
              : stackSize;
          var toOutput = toDistributeThisCycle.withCount(count);

          // Grow by 1 to determine whether the target is full even after a successful transfer.
          final testWithIncreasedCount = distributed.containsKey(pair);
          final increasedCount = testWithIncreasedCount
              ? distributed[pair]!.count
              : 0;
          if (testWithIncreasedCount) toOutput = toOutput.grow(increasedCount);

          final remainder = await insertIntoTunnel(
            tunnel,
            side,
            toOutput,
            true,
          );

          if (remainder == null ||
              remainder.count == (testWithIncreasedCount ? count + 1 : count)) {
            if (force) return;
            if (split && simulate) remainingOutputs--;
            if (!simulate) full.add(pair);
            if (robin) break;
            continue;
          } else if (remainder.isNotEmpty && !simulate) {
            full.add(pair);
          }

          if (!simulate) {
            toOutput = toOutput.shrink(remainder.count);
            distributed[pair] = toOutput;
          }

          leftovers += remainder.count;
          toDistributeThisCycle = toDistributeThisCycle.shrink(count);
          if (toDistributeThisCycle.isEmpty) break;
          splitRemainder--;
          if (!split) break;
        }
      }

      toDistribute = toDistributeThisCycle.grow(leftovers);
      if (leftovers == 0 && distributeAgain) break;
      if (!split) break;
    }

    var failedTransferrals = 0;
    for (final entry in distributed.entries) {
      final remainder = await insertIntoTunnel(
        entry.key.$1,
        entry.key.$2,
        entry.value,
        false,
      );
      failedTransferrals += remainder?.count ?? 0;
    }

    toDistribute = toDistribute.grow(failedTransferrals);
    stackToDistribute = stackToDistribute.withCount(toDistribute.count);
    if (stackToDistribute.isEmpty) stackEnteredFrom = null;
    previousOutputIndex++;
    previousOutputIndex %= amountTargets;
    markDirty();
    sendData();
  }

  /// `insertIntoTunnel`: the remainder, or `null` when the output rejects the stack.
  Future<ItemValue?> insertIntoTunnel(
    BrassTunnelBlockEntity tunnel,
    Direction side,
    ItemValue stack,
    bool simulate,
  ) async {
    if (stack.isEmpty) return stack;
    if (!tunnel.testFlapFilter(side, stack)) return null;

    final below = rt.beAt(worldId, tunnel.pos.toPos().below);
    if (below is! BeltEnvironment) return null;
    final offset = tunnel.pos.toPos().below.relative(side);

    final target = rt.beAt(worldId, offset);
    final hasInput =
        target is DirectBeltInput ||
        target?.getBehaviour<pt.DirectBeltInputBehaviour>() != null;
    if (hasInput) {
      if (!_canInsertAt(worldId, offset, side)) return null;
      final result = await _insertAt(worldId, offset, stack, side, simulate);
      if (result.isEmpty && !simulate) tunnel.flap(side, false);
      return result;
    }

    final env = below as BeltEnvironment;
    if (side == env.movementFacing) {
      final world = this.world;
      if (world != null &&
          !HostBlockGetter(world).isFaceSturdy(offset, side.opposite)) {
        if (!simulate) {
          tunnel.flap(side, true);
          final speed = env.directionAwareBeltMovementSpeed;
          final movementSpeed = math.max(speed.abs(), 1 / 8);
          // `BeltHelper.getVectorForOffset(controllerBE, below.index + additionalOffset)`: the
          // item leaves from the belt itself, not from the tunnel's block centre.
          final additionalOffset = speed > 0 ? 1 : 0;
          final segmentIndex = _segmentIndex(env, tunnel.pos.toPos().below);
          final at = env.vectorForOffset(
            (segmentIndex + additionalOffset).toDouble(),
          );
          final outPos = (at.$1, at.$2 + 6 / 16, at.$3);
          final motion = (
            side.stepX * movementSpeed,
            1 / 8,
            side.stepZ * movementSpeed,
          );
          await spawnItemEntity(world, outPos, stack, velocity: motion);
        }
        return ItemValue.empty;
      }
    }
    return null;
  }

  /// The belt index of the segment at [pos] (`BeltBlockEntity.index`).
  static int _segmentIndex(BeltEnvironment env, Pos pos) {
    for (var i = 0; i < env.beltLength; i++) {
      if (env.positionForOffset(i) == pos) return i;
    }
    return 0;
  }

  /// `testFlapFilter`.
  bool testFlapFilter(Direction side, ItemValue stack) {
    if (filtering.get(side) == null) {
      final adjacent = rt.behaviourAt<FilteringBehaviour>(
        worldId,
        this.pos.toPos().relative(side),
      );
      if (adjacent == null) return true;
      return adjacent.test(stack);
    }
    return filtering.testSide(side, stack);
  }

  /// `flapFilterEmpty`.
  bool flapFilterEmpty(Direction side) {
    if (filtering.get(side) == null) {
      final adjacent = rt.behaviourAt<FilteringBehaviour>(
        worldId,
        this.pos.toPos().relative(side),
      );
      if (adjacent == null) return true;
      return adjacent.filter.isEmpty;
    }
    return filtering.getFilter(side).isEmpty;
  }

  // -- Outputs ---------------------------------------------------------------------------------

  List<(BrassTunnelBlockEntity, Direction)>? gatherValidOutputs() {
    final validOutputs = <(BrassTunnelBlockEntity, Direction)>[];
    final synchronize = selectionModeValue == TunnelSelectionMode.synchronize;
    addValidOutputsOf(this, validOutputs);

    for (final left in [true, false]) {
      BrassTunnelBlockEntity? adjacent = this;
      while (adjacent != null) {
        if (!rt.posLoaded(worldId, adjacent.pos.toPos())) return null;
        adjacent = adjacent.getAdjacent(left);
        if (adjacent == null) continue;
        addValidOutputsOf(adjacent, validOutputs);
      }
    }

    if (!syncedOutputActive && synchronize) return null;
    return validOutputs;
  }

  void addValidOutputsOf(
    BrassTunnelBlockEntity tunnel,
    List<(BrassTunnelBlockEntity, Direction)> validOutputs,
  ) {
    syncSet.add(tunnel);
    final below = rt.beAt(worldId, tunnel.pos.toPos().below);
    if (below is! BeltEnvironment) return;
    final env = below as BeltEnvironment;
    final movementFacing = env.movementFacing;
    final blockState = state;
    if (!isTunnelState(blockState)) return;

    final prioritizeSides = identical(tunnel, this);

    for (final sidePass in [true, false]) {
      if (!prioritizeSides && sidePass) continue;
      for (final direction in Direction.planeHorizontal) {
        if (direction == movementFacing && env.speed == 0) continue;
        if (prioritizeSides &&
            sidePass == (direction.axis == movementFacing.axis))
          continue;
        if (direction == movementFacing.opposite) continue;
        if (!tunnel.sides.contains(direction)) continue;

        final offset = tunnel.pos.toPos().below.relative(direction);
        final potentialFunnel = stateAt(offset.above);
        if (isBeltFunnelState(potentialFunnel) &&
            potentialFunnel['shape'] == 'pulling' &&
            funnelFacing(potentialFunnel) == direction) {
          continue;
        }

        final target = rt.beAt(worldId, offset);
        final hasInput =
            target is DirectBeltInput ||
            target?.getBehaviour<pt.DirectBeltInputBehaviour>() != null;
        if (hasInput) {
          if (_canInsertAt(worldId, offset, direction))
            validOutputs.add((tunnel, direction));
          continue;
        }
        if (direction == movementFacing) {
          final world = this.world;
          if (world != null &&
              !HostBlockGetter(world)
                  .isFaceSturdy(offset, direction.opposite)) {
            validOutputs.add((tunnel, direction));
          }
        }
      }
    }
  }

  // -- Adjacent tunnels ------------------------------------------------------------------------

  bool isConnected(bool leftSide) => leftSide ? connectedLeft : connectedRight;

  BrassTunnelBlockEntity? getAdjacent(bool leftSide) {
    final world = this.world;
    if (world == null) return null;
    final blockState = state;
    if (!isTunnelState(blockState)) return null;
    final axis = blockState.axisOf('axis') ?? Axis.x;
    final base = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
    final direction = leftSide ? base.counterClockWise : base.clockWise;
    final adjacentPos = this.pos.toPos().relative(direction);
    final adjacentState = stateAt(adjacentPos);
    if (adjacentState.key != 'create:brass_tunnel') return null;
    if ((adjacentState.axisOf('axis') ?? Axis.x) != axis) return null;
    final be = rt.beAt(worldId, adjacentPos);
    if (be == null || be.removed) return null;
    return be is BrassTunnelBlockEntity ? be : null;
  }

  bool determineIfConnected(bool leftSide) {
    if (flaps.isEmpty) return false;
    final adjacent = getAdjacent(leftSide);
    return adjacent != null && adjacent.flaps.isNotEmpty;
  }

  @override
  void updateTunnelConnections() {
    super.updateTunnelConnections();
    var changed = false;
    final nowLeft = determineIfConnected(true);
    final nowRight = determineIfConnected(false);

    if (connectedLeft != nowLeft) {
      connectedLeft = nowLeft;
      changed = true;
      final adjacent = getAdjacent(true);
      if (adjacent != null && world != null) {
        adjacent.updateTunnelConnections();
        adjacent.selectionMode.setValue(selectionMode.value);
      }
    }
    if (connectedRight != nowRight) {
      connectedRight = nowRight;
      changed = true;
      final adjacent = getAdjacent(false);
      if (adjacent != null && world != null) {
        adjacent.updateTunnelConnections();
        adjacent.selectionMode.setValue(selectionMode.value);
      }
    }

    filtering.updateFilterPresence();
    if (changed) sendData();
  }

  void _onSelectionModeChanged(int value) {
    for (final left in [true, false]) {
      if (!isConnected(left)) continue;
      final adjacent = getAdjacent(left);
      adjacent?.selectionMode.setValue(value);
    }
  }

  /// `grabAllStacksOfGroup`.
  List<ItemValue> grabAllStacksOfGroup(bool simulate) {
    final list = <ItemValue>[];
    final own = getStackToDistribute();
    if (own.isNotEmpty) {
      list.add(own);
      if (!simulate) setStackToDistribute(ItemValue.empty, null);
    }
    for (final left in [true, false]) {
      BrassTunnelBlockEntity? adjacent = this;
      while (adjacent != null) {
        if (!rt.posLoaded(worldId, adjacent.pos.toPos())) return const [];
        adjacent = adjacent.getAdjacent(left);
        if (adjacent == null) continue;
        final other = adjacent.getStackToDistribute();
        if (other.isEmpty) continue;
        list.add(other);
        if (!simulate) adjacent.setStackToDistribute(ItemValue.empty, null);
      }
    }
    return list;
  }

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag
      ..putBool('SyncedOutput', syncedOutputActive)
      ..putBool('ConnectedLeft', connectedLeft)
      ..putBool('ConnectedRight', connectedRight)
      ..putCompound(
        'StackToDistribute',
        ItemCodec.toTag(stackToDistribute, clientPacket: clientPacket),
      )
      ..putFloat('DistributionProgress', distributionProgress)
      ..putInt('PreviousIndex', previousOutputIndex)
      ..putInt('DistanceLeft', distributionDistanceLeft)
      ..putInt('DistanceRight', distributionDistanceRight);
    if (stackEnteredFrom != null)
      tag.putString('StackEnteredFrom', directionNbtName(stackEnteredFrom!));
    _writeTargets(tag, 'FilteredTargets', _filteredTargets);
    _writeTargets(tag, 'Targets', _targets);
    super.write(tag, clientPacket: clientPacket);
  }

  static void _writeTargets(
    NbtCompound tag,
    String key,
    List<(Pos, Direction)> targets,
  ) {
    tag.putList(key, [
      for (final (p, face) in targets)
        NbtCompound()
          ..putIntArray('Pos', [p.$1, p.$2, p.$3])
          ..putInt('Face', face.data3d),
    ]);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    // The sided filters need the sides before the behaviours read their NBT.
    readSides(tag);
    filtering.updateFilterPresence();

    syncedOutputActive = tag.getBool('SyncedOutput') ?? false;
    connectedLeft = tag.getBool('ConnectedLeft') ?? false;
    connectedRight = tag.getBool('ConnectedRight') ?? false;
    stackToDistribute = ItemCodec.fromAnyNbt(
      tag.getCompound('StackToDistribute'),
    );
    final enteredFrom = tag.getString('StackEnteredFrom');
    stackEnteredFrom = enteredFrom == null
        ? null
        : directionFromNbtName(enteredFrom);
    distributionProgress = tag.getDouble('DistributionProgress') ?? 0;
    previousOutputIndex = tag.getInt('PreviousIndex') ?? 0;
    distributionDistanceLeft = tag.getInt('DistanceLeft') ?? 0;
    distributionDistanceRight = tag.getInt('DistanceRight') ?? 0;
    _targets
      ..clear()
      ..addAll(_readTargets(tag, 'Targets'));
    _filteredTargets
      ..clear()
      ..addAll(_readTargets(tag, 'FilteredTargets'));

    super.read(tag, clientPacket: clientPacket);
    filtering.updateFilterPresence();
  }

  static List<(Pos, Direction)> _readTargets(NbtCompound tag, String key) {
    final out = <(Pos, Direction)>[];
    for (final e in tag.getList(key) ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final p = e.getIntArray('Pos');
      if (p == null || p.length < 3) continue;
      out.add((
        (p[0], p[1], p[2]),
        Direction.from3DDataValue(e.getInt('Face') ?? 0),
      ));
    }
    return out;
  }

  @override
  void onRemoved() {
    super.onRemoved();
    final world = this.world;
    if (world != null && stackToDistribute.isNotEmpty) {
      rt.fire(
        'Dropping the tunnel item',
        () => dropItemAt(world, this.pos.toPos(), stackToDistribute),
      );
    }
    stackToDistribute = ItemValue.empty;
    stackEnteredFrom = null;
  }
}

/// `BrassTunnelItemHandler`: the stack waiting to be distributed (or the belt's own handler).
final class _BrassTunnelInventory implements ItemInventory {
  final BrassTunnelBlockEntity be;

  _BrassTunnelInventory(this.be);

  ItemInventory? get _belt =>
      ItemInventories.at(be.worldId, be.pos.toPos().below);

  @override
  int get slots => 1;

  @override
  ItemValue getStack(int slot) => be.stackToDistribute;

  @override
  int slotLimit(int slot) =>
      be.stackToDistribute.isEmpty ? 64 : be.stackToDistribute.maxStack;

  @override
  bool isItemValid(int slot, ItemValue stack) => true;

  @override
  FutureOr<ItemValue> insert(
    int slot,
    ItemValue stack, {
    bool simulate = false,
  }) async {
    if (!be.hasDistributionBehaviour) {
      final belt = _belt;
      if (belt == null) return stack;
      return belt.insert(slot, stack, simulate: simulate);
    }
    if (!be.canTakeItems) return stack;
    final max = stack.maxStack;
    final remainder = stack.count > max
        ? stack.withCount(stack.count - max)
        : ItemValue.empty;
    if (!simulate) be.setStackToDistribute(stack, null);
    return remainder;
  }

  @override
  FutureOr<ItemValue> extract(
    int slot,
    int amount, {
    bool simulate = false,
  }) async {
    final belt = _belt;
    if (belt == null) return ItemValue.empty;
    return belt.extract(slot, amount, simulate: simulate);
  }
}

// -- Direct belt input helpers ---------------------------------------------------------------

bool _canInsertAt(String worldId, Pos p, Direction side) =>
    _directInputAt(worldId, p)?.canInsertFromSide(side) ?? false;

DirectBeltInput? _directInputAt(String worldId, Pos p) {
  final be = ConveyanceRuntime.i.beAt(worldId, p);
  if (be is DirectBeltInput) return be as DirectBeltInput;
  final behaviour = be?.getBehaviour<pt.DirectBeltInputBehaviour>();
  return behaviour == null ? null : DirectInputAdapter(behaviour);
}

Future<ItemValue> _insertAt(
  String worldId,
  Pos p,
  ItemValue stack,
  Direction side,
  bool simulate,
) async {
  final input = _directInputAt(worldId, p);
  if (input == null) return stack;
  return input.handleInsertion(
    TransportedItemStack(stack),
    side,
    simulate: simulate,
  );
}
