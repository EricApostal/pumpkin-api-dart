// `BeltInventory` (pure): the items on one belt chain, owned by its controller. Moves them
// along the belt, holds them for processing machines, hands them to funnels, tunnels,
// crushers and the block at the end of the belt, and ejects them as entities.
import 'dart:math' as math;

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../behaviours/belt_interfaces.dart';
import 'belt_handlers.dart';
import 'belt_ports.dart';
import 'transported_item.dart';

enum _Ending {
  unresolved(0),
  eject(0),
  insert(.25),
  funnel(.5),
  blocked(.45);

  final double margin;
  const _Ending(this.margin);
}

class BeltInventory {
  final BeltEnvironment env;
  final List<TransportedItemStack> items = [];
  final List<TransportedItemStack> toInsert = [];
  final List<TransportedItemStack> toRemove = [];
  bool beltMovementPositive = false;
  TransportedItemStack? lazyClientItem;

  /// `SEGMENT_WINDOW`.
  static const double segmentWindow = .75;

  BeltInventory(this.env);

  /// `getTransportedItems()`.
  List<TransportedItemStack> getTransportedItems() => items;

  void _flushPending() {
    for (final s in toInsert) {
      _insert(s);
    }
    toInsert.clear();
    items.removeWhere(toRemove.contains);
    toRemove.clear();
  }

  /// `tick()`.
  Future<void> tick() async {
    // Residual item for "smooth" transitions
    final lazy = lazyClientItem;
    if (lazy != null) {
      if (lazy.locked) {
        lazyClientItem = null;
      } else {
        lazy.locked = true;
      }
    }

    // Added/Removed items from previous cycle
    if (toInsert.isNotEmpty || toRemove.isNotEmpty) {
      _flushPending();
      env.notifyUpdate();
    }

    if (env.speed == 0) return;

    // Reverse item collection if belt just reversed
    if (beltMovementPositive != env.directionAwareBeltMovementSpeed > 0) {
      beltMovementPositive = !beltMovementPositive;
      final reversed = items.reversed.toList();
      items
        ..clear()
        ..addAll(reversed);
      env.notifyUpdate();
    }

    // Assuming the first entry is furthest on the belt
    TransportedItemStack? currentItem;

    final beltSpeed = env.directionAwareBeltMovementSpeed;
    final movementFacing = env.movementFacing;
    final horizontal = env.isHorizontal;
    const spacing = 1.0;

    // resolve ending only when items will reach it this tick
    var ending = _Ending.unresolved;

    // Whether any item was moved this tick; the client has to be told, see the end of tick().
    var moved = false;

    var i = 0;
    while (i < items.length) {
      final stackInFront = currentItem;
      currentItem = items[i];
      final current = currentItem;
      current.prevBeltPosition = current.beltPosition;
      current.prevSideOffset = current.sideOffset;

      if (current.stack.isEmpty) {
        items.removeAt(i);
        currentItem = null;
        continue;
      }

      var movement = beltSpeed;

      // Don't move if held by external components
      if (current.lockedExternally) {
        current.lockedExternally = false;
        i++;
        continue;
      }

      // Don't move if other items are waiting in front
      var noMovement = false;
      var currentPos = current.beltPosition;
      if (stackInFront != null) {
        final diff = stackInFront.beltPosition - currentPos;
        if (diff.abs() <= spacing) noMovement = true;
        movement = beltMovementPositive ? math.min(movement, diff - spacing) : math.max(movement, diff + spacing);
      }

      // Don't move beyond the edge
      var diffToEnd = beltMovementPositive ? env.beltLength - currentPos : -currentPos;
      if (diffToEnd.abs() < movement.abs() + 1) {
        if (ending == _Ending.unresolved) ending = _resolveEnding();
        diffToEnd += beltMovementPositive ? -ending.margin : ending.margin;
      }
      final limitedMovement = beltMovementPositive ? math.min(movement, diffToEnd) : math.max(movement, diffToEnd);
      final nextOffset = current.beltPosition + limitedMovement;

      // Belt item processing
      if (horizontal) {
        final before = current.stack;
        if (_handleBeltProcessingAndCheckIfRemoved(current, nextOffset, noMovement)) {
          items.removeAt(i);
          env.notifyUpdate();
          continue;
        }
        if (!identical(before, current.stack)) env.notifyUpdate();
        if (current.locked) {
          i++;
          continue;
        }
      }

      // Belt Funnels
      if (await checkForFunnels(env, beltMovementPositive, current, nextOffset)) {
        i++;
        continue;
      }

      if (noMovement) {
        i++;
        continue;
      }

      // Belt Tunnels
      if (await flapTunnelsAndCheckIfStuck(env, beltMovementPositive, current, nextOffset)) {
        i++;
        continue;
      }

      // Horizontal Crushing Wheels
      if (await checkForCrushers(env, beltMovementPositive, current, nextOffset)) {
        i++;
        continue;
      }

      // Apply Movement
      current.beltPosition += limitedMovement;
      final diffToMiddle = current.targetSideOffset - current.sideOffset;
      current.sideOffset += (diffToMiddle * limitedMovement.abs() * 6.0).clamp(-diffToMiddle.abs(), diffToMiddle.abs()).toDouble();
      currentPos = current.beltPosition;
      if (limitedMovement != 0) moved = true;

      // Movement successful
      if (limitedMovement == movement) {
        i++;
        continue;
      }

      // End reached
      final lastOffset = beltMovementPositive ? env.beltLength - 1 : 0;
      final nextPosition = env.positionForOffset(beltMovementPositive ? env.beltLength : -1);

      if (ending == _Ending.funnel) {
        i++;
        continue;
      }

      if (ending == _Ending.insert) {
        final inputBehaviour = env.directInputAt(nextPosition);
        if (inputBehaviour == null || !inputBehaviour.canInsertFromSide(movementFacing)) {
          i++;
          continue;
        }
        final remainder = await inputBehaviour.handleInsertion(current, movementFacing, simulate: false);
        if (current.stack.matches(remainder)) {
          i++;
          continue;
        }
        current.stack = remainder;
        if (remainder.isEmpty) {
          lazyClientItem = current;
          current.locked = false;
          items.remove(current);
          // The item is gone, the next one looks at its predecessor again.
          flapTunnel(env, lastOffset, movementFacing, false);
          env.notifyUpdate();
          continue;
        }
        flapTunnel(env, lastOffset, movementFacing, false);
        env.notifyUpdate();
        i++;
        continue;
      }

      if (ending == _Ending.blocked) {
        i++;
        continue;
      }

      if (ending == _Ending.eject) {
        await eject(current);
        items.remove(current);
        flapTunnel(env, lastOffset, movementFacing, false);
        env.notifyUpdate();
        continue;
      }
      i++;
    }

    // The client cannot move the items itself: unlike the Java client, it does not tick a copy of
    // the inventory, it only renders the items of the update tag and interpolates `PrevPos` to
    // `Pos` (`BeltRenderer.renderItem`). So every tick that moved an item has to push a new tag;
    // without this the tag stays at the one written when the item was inserted and the item never
    // moves on screen. (Java gets away without it because `BeltInventory.tick` also runs on the
    // client, see its `onClient` flag.)
    if (moved) env.notifyUpdate();
  }

  bool _handleBeltProcessingAndCheckIfRemoved(TransportedItemStack currentItem, double nextOffset, bool noMovement) {
    final currentSegment = currentItem.beltPosition.floor();

    // Continue processing if held
    if (currentItem.locked) {
      final processingBehaviour = _processingAtSegment(currentSegment);
      final stackHandlerBehaviour = _handlerAtSegment(currentSegment);
      if (stackHandlerBehaviour == null) return false;
      if (processingBehaviour == null) {
        currentItem.locked = false;
        env.notifyUpdate();
        return false;
      }
      final result = processingBehaviour.handleHeldItem(currentItem, stackHandlerBehaviour);
      if (result == ProcessingResult.remove) return true;
      if (result == ProcessingResult.hold) return false;
      currentItem.locked = false;
      env.notifyUpdate();
      return false;
    }

    if (noMovement) return false;

    // See if any new belt processing catches the item
    if (currentItem.beltPosition > .5 || beltMovementPositive) {
      final firstUpcomingSegment = (currentItem.beltPosition + (beltMovementPositive ? .5 : -.5)).truncate();
      final step = beltMovementPositive ? 1 : -1;
      for (
        var segment = firstUpcomingSegment;
        beltMovementPositive ? segment + .5 <= nextOffset : segment + .5 >= nextOffset;
        segment += step
      ) {
        final processingBehaviour = _processingAtSegment(segment);
        final stackHandlerBehaviour = _handlerAtSegment(segment);
        if (processingBehaviour == null) continue;
        if (stackHandlerBehaviour == null) continue;
        if (env.isProcessingBlocked(env.positionForOffset(segment))) continue;
        final result = processingBehaviour.handleReceivedItem(currentItem, stackHandlerBehaviour);
        if (result == ProcessingResult.remove) return true;
        if (result == ProcessingResult.hold) {
          currentItem.beltPosition = segment + .5 + (beltMovementPositive ? 1 / 512 : -1 / 512);
          currentItem.locked = true;
          env.notifyUpdate();
          return false;
        }
      }
    }
    return false;
  }

  BeltProcessing? _processingAtSegment(int segment) => env.processingAt(env.positionForOffset(segment).aboveBy(2));

  TransportedItemStackHandler? _handlerAtSegment(int segment) => env.stackHandlerAt(env.positionForOffset(segment));

  _Ending _resolveEnding() {
    final nextPosition = env.positionForOffset(beltMovementPositive ? env.beltLength : -1);
    final inputBehaviour = env.directInputAt(nextPosition);
    if (inputBehaviour != null) return _Ending.insert;
    if (env.hasSolidSide(nextPosition, env.movementFacing.opposite)) return _Ending.blocked;
    return _Ending.eject;
  }

  /// `canInsertAt(segment)`.
  bool canInsertAt(int segment) => canInsertAtFromSide(segment, Direction.up);

  /// `canInsertAtFromSide(segment, side)`.
  bool canInsertAtFromSide(int segment, Direction side) {
    var segmentPos = segment.toDouble();
    if (env.movementFacing == side.opposite) return false;
    if (env.movementFacing != side) {
      segmentPos += .5;
    } else if (!beltMovementPositive) {
      segmentPos += 1;
    }
    for (final stack in items) {
      if (_isBlocking(segment, side, segmentPos, stack)) return false;
    }
    for (final stack in toInsert) {
      if (_isBlocking(segment, side, segmentPos, stack)) return false;
    }
    return true;
  }

  bool _isBlocking(int segment, Direction side, double segmentPos, TransportedItemStack stack) {
    final currentPos = stack.beltPosition;
    return stack.insertedAt == segment &&
        stack.insertedFrom == side &&
        (beltMovementPositive ? currentPos <= segmentPos + 1 : currentPos >= segmentPos - 1);
  }

  /// `addItem(newStack)`.
  void addItem(TransportedItemStack newStack) => toInsert.add(newStack);

  void _insert(TransportedItemStack newStack) {
    if (items.isEmpty) {
      items.add(newStack);
    } else {
      var index = 0;
      for (final stack in items) {
        if ((stack.compareTo(newStack) > 0) == beltMovementPositive) break;
        index++;
      }
      items.insert(index, newStack);
    }
  }

  /// `getStackAtOffset(offset)`.
  TransportedItemStack? getStackAtOffset(int offset) {
    final min = offset.toDouble();
    final max = offset + 1.0;
    for (final stack in items) {
      if (toRemove.contains(stack)) continue;
      if (stack.beltPosition > max) continue;
      if (stack.beltPosition > min) return stack;
    }
    return null;
  }

  /// Applies pending insertions and removals (the start of `write`).
  void flush() {
    if (toInsert.isNotEmpty || toRemove.isNotEmpty) _flushPending();
  }

  /// `eject(stack)`: drops the item beside the belt end with the belt's motion.
  Future<void> eject(TransportedItemStack stack) async {
    final ejected = stack.stack;
    var outPos = env.vectorForOffset(stack.beltPosition);
    final movementSpeed = math.max(env.beltMovementSpeed.abs(), 1 / 8);
    final dir = env.beltChainDirection;
    final outMotion = (dir.x * movementSpeed, dir.y * movementSpeed + 1 / 8, dir.z * movementSpeed);
    final len = math.sqrt(outMotion.$1 * outMotion.$1 + outMotion.$2 * outMotion.$2 + outMotion.$3 * outMotion.$3);
    if (len > 0) {
      outPos = (outPos.$1 + outMotion.$1 / len * 0.001, outPos.$2 + outMotion.$2 / len * 0.001, outPos.$3 + outMotion.$3 / len * 0.001);
    }
    await env.spawnItem(ejected, (outPos.$1, outPos.$2 + 6 / 16, outPos.$3), outMotion);
  }

  /// `ejectAll()`.
  Future<void> ejectAll() async {
    final all = List.of(items);
    items.clear();
    for (final s in all) {
      await eject(s);
    }
  }

  /// `applyToEachWithin(position, maxDistanceToPosition, processFunction)`.
  void applyToEachWithin(double position, double maxDistanceToPosition, ItemProcessor processFunction) {
    var dirty = false;
    for (final transported in List.of(items)) {
      if (toRemove.contains(transported)) continue;
      final stackBefore = transported.stack;
      if ((position - transported.beltPosition).abs() >= maxDistanceToPosition) continue;
      final result = processFunction(transported);
      if (result == null || result.didntChangeFrom(stackBefore)) continue;
      dirty = true;
      final held = result.heldOutput;
      if (held != null) {
        held.beltPosition = position.truncate() + .5 - (beltMovementPositive ? 1 / 512 : -1 / 512);
        toInsert.add(held);
      }
      toInsert.addAll(result.outputs!);
      toRemove.add(transported);
    }
    if (dirty) env.notifyUpdate();
  }
}

/// `BeltHelper`-style helper: whether a position is one of the segment positions (tests).
bool isSegment(Pos pos, BeltEnvironment env) {
  for (var i = 0; i < env.beltLength; i++) {
    if (env.positionForOffset(i) == pos) return true;
  }
  return false;
}
