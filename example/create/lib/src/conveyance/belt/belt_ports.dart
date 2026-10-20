// The environment of a belt inventory (pure interfaces): what the belt, its neighbours and the
// funnels, tunnels and crushing wheels next to it offer to `BeltInventory` and the interaction
// handlers. The block entity implements [BeltEnvironment]; the tests use a fake.
import 'dart:async';

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../behaviours/belt_interfaces.dart';
import '../items/item_data.dart';

/// `VersionedInventoryTrackerBehaviour`: remembers the version of an inventory at which nothing
/// could be transferred, to wait for a change.
class VersionTracker {
  int _ignoredId = -1;
  int _ignoredVersion = -1;

  /// `stillWaiting(handler)`: [version] is `(id, version)` of the inventory, `null` when it does
  /// not count changes.
  bool stillWaiting((int, int)? version) =>
      version != null &&
      version.$1 == _ignoredId &&
      version.$2 == _ignoredVersion;

  /// `awaitNewVersion(handler)`.
  void awaitNewVersion((int, int)? version) {
    if (version != null) {
      _ignoredId = version.$1;
      _ignoredVersion = version.$2;
    }
  }

  /// `reset()`.
  void reset() {
    _ignoredVersion = -1;
    _ignoredId = -1;
  }
}

/// The block entity of a funnel as a belt funnel sees it (`FunnelBlockEntity`).
abstract interface class FunnelPort {
  /// Whether the funnel has an inventory manipulation behaviour to insert with.
  bool get hasInserting;

  /// Whether a filter exists and rejects [stack] (`filtering != null && !filtering.test(stack)`).
  bool filterRejects(ItemValue stack);

  /// The version of the inventory behind the funnel, `null` when there is none.
  (int, int)? get inventoryVersion;

  /// `getAmountToExtract()`.
  int get amountToExtract;

  /// `getModeToExtract()`.
  ExtractionCountMode get modeToExtract;

  /// `inserting.insert(stack)` / `inserting.simulate().insert(stack)`: the remainder.
  Future<ItemValue> insert(ItemValue stack, {required bool simulate});

  /// `flap(inward)`.
  void flap(bool inward);

  /// `onTransfer(stack)`.
  void onTransfer(ItemValue stack);
}

/// A belt funnel above a belt segment: its block state and block entity.
abstract interface class BeltFunnelPort {
  /// `HORIZONTAL_FACING`.
  Direction get facing;

  /// `BeltFunnelBlock.SHAPE`: `retracted`, `extended`, `pushing` or `pulling`.
  String get shape;

  /// `POWERED`.
  bool get powered;

  /// The funnel block entity, `null` when it is missing.
  FunnelPort? get entity;
}

/// A belt tunnel above a belt segment.
abstract interface class BeltTunnelPort {
  /// Position of the tunnel block.
  Pos get position;

  /// Whether the tunnel is a brass tunnel (`BrassTunnelBlockEntity`).
  bool get isBrass;

  /// `hasDistributionBehaviour()` (brass tunnels).
  bool get hasDistributionBehaviour;

  /// `canTakeItems()` (brass tunnels).
  bool get canTakeItems;

  /// `getStackToDistribute()` (brass tunnels; empty for the others).
  ItemValue getStackToDistribute();

  /// `testFlapFilter(side, stack)` (brass tunnels; `true` for the others).
  bool testFlapFilter(Direction side, ItemValue stack);

  /// `canInsert(side, stack)` (brass tunnels).
  bool canInsert(Direction side, ItemValue stack);

  /// `setStackToDistribute(stack, enteredFrom)` (brass tunnels).
  void setStackToDistribute(ItemValue stack, Direction? enteredFrom);

  /// Whether the tunnel is an andesite tunnel with a junction shape (`isJunction`).
  bool get isAndesiteJunction;

  /// `HORIZONTAL_AXIS` of the tunnel.
  Axis get horizontalAxis;

  /// Whether the tunnel has a flap on [side] (`flaps.containsKey(side)`).
  bool hasFlap(Direction side);

  /// `flap(side, inward)`.
  void flap(Direction side, bool inward);

  /// Items passed the tunnel (`AccumulatedItemCountDisplaySource`).
  void itemReceived(int amount);
}

/// A crushing wheel controller above a belt segment.
abstract interface class BeltCrusherPort {
  /// `CrushingWheelControllerBlock.FACING`.
  Direction get facing;

  /// Whether the controller has its block entity.
  bool get hasEntity;

  /// `TransferUtil.insertItemStacked(crusherBE.inventory, stack, false)`: the remainder.
  Future<ItemValue> insert(ItemValue stack);
}

/// What `BeltInventory` needs to know and do about its belt and the world around it.
abstract interface class BeltEnvironment {
  /// `getSpeed()` of the controller.
  double get speed;

  /// `getBeltMovementSpeed()`.
  double get beltMovementSpeed;

  /// `getDirectionAwareBeltMovementSpeed()`.
  double get directionAwareBeltMovementSpeed;

  /// `getMovementFacing()`.
  Direction get movementFacing;

  /// Whether the controller's slope is horizontal.
  bool get isHorizontal;

  /// `beltLength`.
  int get beltLength;

  /// `BeltHelper.getPositionForOffset(belt, offset)`.
  Pos positionForOffset(int offset);

  /// `BeltHelper.getVectorForOffset(belt, offset)`.
  Vec3 vectorForOffset(double offset);

  /// `getBeltChainDirection()`.
  Pos get beltChainDirection;

  /// `level.isLoaded(pos)`.
  bool isLoaded(Pos pos);

  /// The direct input behaviour of the block entity at [pos].
  DirectBeltInput? directInputAt(Pos pos);

  /// The belt processing behaviour of the block entity at [pos].
  BeltProcessing? processingAt(Pos pos);

  /// The stack handler behaviour of the block entity at [pos].
  TransportedItemStackHandler? stackHandlerAt(Pos pos);

  /// `BeltProcessingBehaviour.isBlocked(world, processingSpace)`.
  bool isProcessingBlocked(Pos processingSpace);

  /// `BlockHelper.hasBlockSolidSide(state, world, pos, side)`.
  bool hasSolidSide(Pos pos, Direction side);

  /// The belt funnel in the block above segment [segment], `null` when there is none.
  BeltFunnelPort? funnelAbove(int segment);

  /// The tunnel in the block above segment [segment]
  /// (`BeltTunnelInteractionHandler.getTunnelOnPosition`), regardless of the belt's slope: the
  /// horizontal-only guard of `getTunnelOnSegment` lives in `belt_handlers.dart`.
  BeltTunnelPort? tunnelOnSegment(int segment);

  /// The brass tunnel at [segment] if there is one (for `stuckAtTunnel`).
  BeltTunnelPort? brassTunnelAbove(int segment);

  /// The crushing wheel controller above segment [segment].
  BeltCrusherPort? crusherAbove(int segment);

  /// The belt's inventory version tracker.
  VersionTracker get versionTracker;

  /// `notifyUpdate()`.
  void notifyUpdate();

  /// Spawns the item as an entity (`BeltInventory.eject`).
  FutureOr<void> spawnItem(ItemValue stack, Vec3 position, Vec3 motion);
}
