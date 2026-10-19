// `ConnectivityHandler` and `IMultiBlockEntityContainer` (pure): blocks that merge into one
// multiblock with a controller (fluid tanks, item vaults). The search and the merging are the
// Java ones; the parts are reached through [MultiPartWorld].
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_storage.dart';
import 'fluid_stack.dart';

/// `IMultiBlockEntityContainer` (+ `.Fluid`).
abstract interface class MultiPart {
  /// The block entity type, two parts only merge when it is the same.
  String get partType;

  Pos get partPos;
  bool get isRemoved;

  /// `getController()`: the controller's position (this one when it is the controller).
  Pos get controller;

  /// `getControllerBE()`: the controller, `null` when it is not loaded.
  MultiPart? get controllerPart;

  bool get isController;

  /// `setController(pos)`.
  void setController(Pos pos);

  /// `removeController(keepContents)`.
  void removeController(bool keepContents);

  /// `preventConnectivityUpdate()`.
  void preventConnectivityUpdate();

  /// `notifyMultiUpdated()`.
  void notifyMultiUpdated();

  Object? get extraData;
  set extraData(Object? data);

  /// `modifyExtraData(data)`.
  Object? modifyExtraData(Object? data);

  Axis get mainConnectionAxis;

  /// `getMaxLength(longAxis, width)`.
  int getMaxLength(Axis longAxis, int width);

  int get maxWidth;
  int get height;
  set height(int value);
  int get width;
  set width(int value);

  // -- IMultiBlockEntityContainer.Fluid ------------------------------------------------------
  bool get hasTank;
  int getTankSize(int tank);
  void setTankSize(int tank, int blocks);
  FluidTank? getTank(int tank);
  FStack getFluid(int tank);
}

/// Looks up parts in a world.
abstract interface class MultiPartWorld {
  /// The part of [type] at [pos] (not removed), `null` if there is none.
  MultiPart? partAt(String type, Pos pos);

  /// The block entity at [pos] if it is a part of any type.
  MultiPart? anyPartAt(Pos pos);

  /// Called when the fluid capability of the part at [pos] changes (`invalidateCapabilities`).
  void invalidateCapabilities(Pos pos);
}

abstract final class ConnectivityHandler {
  /// `formMulti(be)`.
  static void formMulti(MultiPartWorld level, MultiPart be) {
    final cache = SearchCache();
    _formMulti(be.partType, level, cache, [be]);
  }

  static void _formMulti(String type, MultiPartWorld level, SearchCache cache, List<MultiPart> frontier) {
    final creationQueue = <(int, MultiPart)>[];
    final visited = <Pos>{};
    final mainAxis = frontier.first.mainConnectionAxis;

    // Essentially, if it's a vertical multi then the search won't be restricted by Y;
    // alternately, a horizontal multi search shouldn't be restricted by X or Z.
    var minX = mainAxis == Axis.y ? 0x7fffffff : -0x80000000;
    var minY = mainAxis != Axis.y ? 0x7fffffff : -0x80000000;
    var minZ = mainAxis == Axis.y ? 0x7fffffff : -0x80000000;

    for (final be in frontier) {
      final pos = be.partPos;
      if (pos.x < minX) minX = pos.x;
      if (pos.y < minY) minY = pos.y;
      if (pos.z < minZ) minZ = pos.z;
    }

    if (mainAxis == Axis.y) minX -= frontier.first.maxWidth;
    if (mainAxis != Axis.y) minY -= frontier.first.maxWidth;
    if (mainAxis == Axis.y) minZ -= frontier.first.maxWidth;

    while (frontier.isNotEmpty) {
      final part = frontier.removeAt(0);
      final partPos = part.partPos;
      if (visited.contains(partPos)) continue;
      visited.add(partPos);

      final amount = _tryToFormNewMulti(level, part, cache, true);
      if (amount > 1) creationQueue.add((amount, part));

      for (final axis in Axis.values) {
        final dir = Direction.fromAxisAndDirection(axis, AxisDirection.negative);
        final next = partPos.relative(dir);

        if (next.x <= minX || next.y <= minY || next.z <= minZ) continue;
        if (visited.contains(next)) continue;

        final nextBe = level.partAt(type, next);
        if (nextBe == null) continue;
        if (nextBe.isRemoved) continue;
        frontier.add(nextBe);
      }
    }

    visited.clear();

    // Largest first (PriorityQueue with the amount descending).
    final order = List<(int, MultiPart)>.of(creationQueue)..sort((a, b) => b.$1.compareTo(a.$1));
    for (final next in order) {
      final toCreate = next.$2;
      if (visited.contains(toCreate.partPos)) continue;
      visited.add(toCreate.partPos);
      _tryToFormNewMulti(level, toCreate, cache, false);
    }
  }

  static int _tryToFormNewMulti(MultiPartWorld level, MultiPart be, SearchCache cache, bool simulate) {
    var bestWidth = 1;
    var bestAmount = -1;

    if (!be.isController) return 0;

    final radius = be.maxWidth;
    for (var w = 1; w <= radius; w++) {
      final amount = _tryToFormNewMultiOfWidth(level, be, w, cache, true);
      if (amount < bestAmount) continue;
      bestWidth = w;
      bestAmount = amount;
    }

    if (!simulate) {
      final beWidth = be.width;
      if (beWidth == bestWidth && beWidth * beWidth * be.height == bestAmount) return bestAmount;

      splitMultiAndInvalidate(level, be, cache, false);
      if (be.hasTank) be.setTankSize(0, bestAmount);

      _tryToFormNewMultiOfWidth(level, be, bestWidth, cache, false);

      be.preventConnectivityUpdate();
      be.width = bestWidth;
      be.height = bestAmount ~/ bestWidth ~/ bestWidth;
      be.notifyMultiUpdated();
    }

    return bestAmount;
  }

  static Pos _partPosition(Axis axis, Pos origin, int yOffset, int xOffset, int zOffset) => switch (axis) {
    Axis.x => origin.offset(yOffset, xOffset, zOffset),
    Axis.y => origin.offset(xOffset, yOffset, zOffset),
    Axis.z => origin.offset(xOffset, zOffset, yOffset),
  };

  static int _tryToFormNewMultiOfWidth(MultiPartWorld level, MultiPart be, int width, SearchCache cache, bool simulate) {
    var amount = 0;
    var height = 0;
    final type = be.partType;
    final origin = be.partPos;

    // optional fluid handling
    FluidTank? beTank;
    var fluid = FStack.empty;
    if (be.hasTank) {
      beTank = be.getTank(0);
      fluid = beTank?.fluid ?? FStack.empty;
    }

    final axis = be.mainConnectionAxis;

    search:
    for (var yOffset = 0; yOffset < be.getMaxLength(axis, width); yOffset++) {
      for (var xOffset = 0; xOffset < width; xOffset++) {
        for (var zOffset = 0; zOffset < width; zOffset++) {
          final pos = _partPosition(axis, origin, yOffset, xOffset, zOffset);
          final part = cache.getOrCache(type, level, pos);
          if (part == null) break search;

          final controller = part;
          final otherWidth = controller.width;
          if (otherWidth > width) break search;
          if (otherWidth == width && controller.height == be.getMaxLength(axis, width)) break search;

          final conAxis = controller.mainConnectionAxis;
          if (axis != conAxis) break search;

          final conPos = controller.partPos;
          if (conPos != origin) {
            if (axis == Axis.y) {
              // vertical multi, like a FluidTank
              if (conPos.x < origin.x) break search;
              if (conPos.z < origin.z) break search;
              if (conPos.x + otherWidth > origin.x + width) break search;
              if (conPos.z + otherWidth > origin.z + width) break search;
            } else {
              // horizontal multi, like an ItemVault
              if (axis == Axis.z && conPos.x < origin.x) break search;
              if (conPos.y < origin.y) break search;
              if (axis == Axis.x && conPos.z < origin.z) break search;
              if (axis == Axis.z && conPos.x + otherWidth > origin.x + width) break search;
              if (conPos.y + otherWidth > origin.y + width) break search;
              if (axis == Axis.x && conPos.z + otherWidth > origin.z + width) break search;
            }
          }

          if (controller.hasTank) {
            final otherFluid = controller.getFluid(0);
            if (fluid.isNotEmpty && otherFluid.isNotEmpty && !fluid.isSameFluid(otherFluid)) break search;
          }
        }
      }

      amount += width * width;
      height++;
    }

    if (simulate) return amount;

    var extraData = be.extraData;

    for (var yOffset = 0; yOffset < height; yOffset++) {
      for (var xOffset = 0; xOffset < width; xOffset++) {
        for (var zOffset = 0; zOffset < width; zOffset++) {
          final pos = _partPosition(axis, origin, yOffset, xOffset, zOffset);
          final part = level.partAt(type, pos);
          if (part == null) continue;
          if (identical(part, be)) continue;

          extraData = be.modifyExtraData(extraData);

          if (part.hasTank) {
            final tankAt = part.getTank(0);
            final fluidAt = tankAt?.fluid ?? FStack.empty;
            if (tankAt != null && fluidAt.isNotEmpty) {
              // making this generic would be a rather large mess, unfortunately
              if (beTank != null && fluid.isEmpty && beTank is CreativeSmartFluidTank) {
                beTank.setContainedFluid(fluidAt);
              }
              if (be.hasTank && beTank != null) beTank.fill(fluidAt, simulate: false);
            }
            tankAt?.drain(tankAt.capacity, simulate: false);
          }

          splitMultiAndInvalidate(level, part, cache, false);
          part.setController(origin);
          part.preventConnectivityUpdate();
          cache.put(pos, be);

          part.height = height;
          part.width = width;
          part.notifyMultiUpdated();
        }
      }
    }

    be.extraData = extraData;
    return amount;
  }

  /// `splitMulti(be)`.
  static void splitMulti(MultiPartWorld level, MultiPart be) => splitMultiAndInvalidate(level, be, null, false);

  /// `splitMultiAndInvalidate(be, cache, tryReconnect)`; [tryReconnect] helps whenever only a few
  /// tanks have been removed.
  static void splitMultiAndInvalidate(MultiPartWorld level, MultiPart partIn, SearchCache? cache, bool tryReconnect) {
    final controllerPart = partIn.controllerPart;
    if (controllerPart == null) return;
    final be = controllerPart;

    final height = be.height;
    final width = be.width;
    if (width == 1 && height == 1) return;

    final origin = be.partPos;
    final frontier = <MultiPart>[];
    final axis = be.mainConnectionAxis;

    // fluid handling, if present
    var toDistribute = FStack.empty;
    var maxCapacity = 0;
    if (be.hasTank) {
      toDistribute = be.getFluid(0);
      maxCapacity = be.getTankSize(0);
      if (toDistribute.isNotEmpty && !be.isRemoved) toDistribute = toDistribute.shrink(maxCapacity);
      be.setTankSize(0, 1);
    }

    for (var yOffset = 0; yOffset < height; yOffset++) {
      for (var xOffset = 0; xOffset < width; xOffset++) {
        for (var zOffset = 0; zOffset < width; zOffset++) {
          final pos = _partPosition(axis, origin, yOffset, xOffset, zOffset);
          final partAt = level.partAt(be.partType, pos);
          if (partAt == null) continue;
          if (partAt.controller != origin) continue;

          final controllerBE = partAt.controllerPart;
          partAt.extraData = controllerBE?.extraData;
          partAt.removeController(true);

          if (toDistribute.isNotEmpty && !identical(partAt, be)) {
            final tank = partAt.hasTank ? partAt.getTank(0) : null;
            // making this generic would be a rather large mess, unfortunately
            if (tank is CreativeSmartFluidTank) {
              if (tank.isEmpty) tank.setContainedFluid(toDistribute);
            } else {
              final split = maxCapacity < toDistribute.amount ? maxCapacity : toDistribute.amount;
              final copy = toDistribute.withAmount(split);
              toDistribute = toDistribute.shrink(split);
              tank?.fill(copy, simulate: false);
            }
          }

          if (tryReconnect) {
            frontier.add(partAt);
            partAt.preventConnectivityUpdate();
          }
          cache?.put(pos, partAt);
        }
      }
    }

    if (be.hasTank) level.invalidateCapabilities(be.partPos);

    if (tryReconnect) _formMulti(be.partType, level, cache ?? SearchCache(), frontier);
  }

  /// `isConnected(level, pos, other)`.
  static bool isConnected(MultiPartWorld level, Pos pos, Pos other) {
    final one = level.anyPartAt(pos);
    final two = level.anyPartAt(other);
    if (one == null || two == null) return false;
    return one.controller == two.controller;
  }
}

/// `SearchCache`.
class SearchCache {
  final Map<Pos, MultiPart?> controllerMap = {};

  void put(Pos pos, MultiPart target) => controllerMap[pos] = target;

  void putEmpty(Pos pos) => controllerMap[pos] = null;

  bool hasVisited(Pos pos) => controllerMap.containsKey(pos);

  MultiPart? getOrCache(String type, MultiPartWorld level, Pos pos) {
    if (hasVisited(pos)) return controllerMap[pos];
    final partAt = level.partAt(type, pos);
    if (partAt == null) {
      putEmpty(pos);
      return null;
    }
    final controller = level.anyPartAt(partAt.controller);
    if (controller == null) {
      putEmpty(pos);
      return null;
    }
    put(pos, controller);
    return controller;
  }
}
