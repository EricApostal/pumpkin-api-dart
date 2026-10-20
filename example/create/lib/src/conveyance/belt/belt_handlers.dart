// The interactions of a moving belt item with funnels, tunnels and crushing wheels (pure):
// `BeltFunnelInteractionHandler`, `BeltTunnelInteractionHandler`,
// `BeltCrusherInteractionHandler`.
import 'dart:math' as math;

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../items/item_data.dart';
import 'belt_ports.dart';
import 'transported_item.dart';

/// `BeltFunnelInteractionHandler.checkForFunnels`: returns whether the item must not move on.
Future<bool> checkForFunnels(
  BeltEnvironment env,
  bool beltMovementPositive,
  TransportedItemStack currentItem,
  double nextOffset,
) async {
  var firstUpcomingSegment = currentItem.beltPosition.floor();
  final step = beltMovementPositive ? 1 : -1;
  firstUpcomingSegment = firstUpcomingSegment.clamp(0, math.max(0, env.beltLength - 1));
  for (
    var segment = firstUpcomingSegment;
    beltMovementPositive ? segment <= nextOffset : segment + 1 >= nextOffset;
    segment += step
  ) {
    final funnel = env.funnelAbove(segment);
    if (funnel == null) continue;
    final funnelFacing = funnel.facing;
    final movementFacing = env.movementFacing;
    final blocking = funnelFacing == movementFacing.opposite;
    if (funnelFacing == movementFacing) continue;
    if (funnel.shape == 'pushing') continue;

    var funnelEntry = segment + .5;
    if (funnel.shape == 'extended') funnelEntry += .499 * (beltMovementPositive ? -1 : 1);
    final hasCrossed = (nextOffset > funnelEntry && beltMovementPositive) || (nextOffset < funnelEntry && !beltMovementPositive);
    if (!hasCrossed) return false;
    if (blocking) currentItem.beltPosition = funnelEntry;

    if (funnel.powered) {
      if (blocking) return true;
      continue;
    }

    final be = funnel.entity;
    if (be == null) return true;
    if (!be.hasInserting || be.filterRejects(currentItem.stack)) {
      if (blocking) return true;
      continue;
    }
    if (env.versionTracker.stillWaiting(be.inventoryVersion)) continue;

    final amountToExtract = be.amountToExtract;
    final modeToExtract = be.modeToExtract;
    var toInsert = currentItem.stack;
    if (amountToExtract > toInsert.count && modeToExtract != ExtractionCountMode.upTo) {
      if (blocking) return true;
      continue;
    }
    if (amountToExtract != -1 && modeToExtract != ExtractionCountMode.upTo) {
      toInsert = toInsert.withCount(math.min(amountToExtract, toInsert.count));
      final simulated = await be.insert(toInsert, simulate: true);
      if (simulated.isNotEmpty) {
        if (blocking) return true;
        continue;
      } else {
        env.versionTracker.awaitNewVersion(be.inventoryVersion);
      }
    }

    var remainder = await be.insert(toInsert, simulate: false);
    if (toInsert.matches(remainder)) {
      env.versionTracker.awaitNewVersion(be.inventoryVersion);
      if (blocking) return true;
      continue;
    }

    final notFilled = currentItem.stack.count - toInsert.count;
    if (remainder.isNotEmpty) {
      remainder = remainder.grow(notFilled);
    } else if (notFilled > 0) {
      remainder = currentItem.stack.withCount(notFilled);
    }

    be.flap(true);
    be.onTransfer(toInsert);
    currentItem.stack = remainder;
    env.notifyUpdate();
    if (blocking) return true;
  }
  return false;
}

/// `BeltTunnelInteractionHandler.getTunnelOnSegment`: only a horizontal belt has tunnels on its
/// segments, so a sloped belt cannot grab the tunnel of a neighbouring one.
BeltTunnelPort? tunnelOnHorizontalSegment(BeltEnvironment env, int offset) =>
    env.isHorizontal ? env.tunnelOnSegment(offset) : null;

/// `BeltTunnelInteractionHandler.flapTunnel`.
void flapTunnel(BeltEnvironment env, int offset, Direction side, bool inward) {
  tunnelOnHorizontalSegment(env, offset)?.flap(side, inward);
}

/// `BeltTunnelInteractionHandler.stuckAtTunnel`.
bool stuckAtTunnel(BeltEnvironment env, int offset, ItemValue stack, Direction movementDirection) {
  final tunnel = env.brassTunnelAbove(offset);
  if (tunnel == null) return false;
  return !tunnel.canInsert(movementDirection.opposite, stack);
}

/// `BeltTunnelInteractionHandler.flapTunnelsAndCheckIfStuck`: returns whether the item is stuck
/// (or was taken by a brass tunnel).
Future<bool> flapTunnelsAndCheckIfStuck(
  BeltEnvironment env,
  bool beltMovementPositive,
  TransportedItemStack current,
  double nextOffset,
) async {
  final currentSegment = current.beltPosition.floor();
  var upcomingSegment = nextOffset.floor();
  final movementFacing = env.movementFacing;
  if (!beltMovementPositive && nextOffset == 0) upcomingSegment = -1;
  if (currentSegment == upcomingSegment) return false;

  if (stuckAtTunnel(env, upcomingSegment, current.stack, movementFacing)) {
    current.beltPosition = currentSegment + (beltMovementPositive ? .99 : .01);
    return true;
  }

  var removed = false;
  final nextTunnel = tunnelOnHorizontalSegment(env, upcomingSegment);
  final transferred = current.stack.count;

  if (nextTunnel != null && nextTunnel.isBrass) {
    if (nextTunnel.hasDistributionBehaviour) {
      if (!nextTunnel.canTakeItems) return true;
      nextTunnel.setStackToDistribute(current.stack, movementFacing.opposite);
      current.stack = ItemValue.empty;
      env.notifyUpdate();
      removed = true;
    }
  } else if (nextTunnel != null) {
    if (current.stack.count > 1 && nextTunnel.isAndesiteJunction && movementFacing.axis == nextTunnel.horizontalAxis) {
      for (final d in Direction.horizontals) {
        if (d.axis == nextTunnel.horizontalAxis) continue;
        if (!nextTunnel.hasFlap(d)) continue;
        final Pos outpos = nextTunnel.position.below.relative(d);
        if (!env.isLoaded(outpos)) return true;
        final behaviour = env.directInputAt(outpos);
        if (behaviour == null) continue;
        if (!behaviour.canInsertFromSide(d)) continue;
        final toinsert = current.stack.withCount(1);
        final remainder = await behaviour.handleInsertion(TransportedItemStack(toinsert), d, simulate: false);
        if (remainder.isNotEmpty) return true;
        flapTunnel(env, upcomingSegment, d, false);
        current.stack = current.stack.shrink(1);
        env.notifyUpdate();
        if (current.stack.count <= 1) break;
      }
    }
  }

  flapTunnel(env, currentSegment, movementFacing, false);
  flapTunnel(env, upcomingSegment, movementFacing.opposite, true);
  if (nextTunnel != null) nextTunnel.itemReceived(transferred);

  return removed;
}

/// `BeltCrusherInteractionHandler.checkForCrushers`.
Future<bool> checkForCrushers(
  BeltEnvironment env,
  bool beltMovementPositive,
  TransportedItemStack currentItem,
  double nextOffset,
) async {
  var firstUpcomingSegment = currentItem.beltPosition.floor();
  final step = beltMovementPositive ? 1 : -1;
  firstUpcomingSegment = firstUpcomingSegment.clamp(0, math.max(0, env.beltLength - 1));
  for (
    var segment = firstUpcomingSegment;
    beltMovementPositive ? segment <= nextOffset : segment + 1 >= nextOffset;
    segment += step
  ) {
    final crusher = env.crusherAbove(segment);
    if (crusher == null) continue;
    if (crusher.facing != env.movementFacing) continue;

    var crusherEntry = segment + .5;
    crusherEntry += .399 * (beltMovementPositive ? -1 : 1);
    final postCrusherEntry = crusherEntry + .799 * (!beltMovementPositive ? -1 : 1);
    final hasCrossed =
        (nextOffset > crusherEntry && nextOffset < postCrusherEntry && beltMovementPositive) ||
        (nextOffset < crusherEntry && nextOffset > postCrusherEntry && !beltMovementPositive);
    if (!hasCrossed) return false;

    currentItem.beltPosition = crusherEntry;
    if (!crusher.hasEntity) return true;

    final toInsert = currentItem.stack;
    var remainder = await crusher.insert(toInsert);
    if (toInsert.matches(remainder)) return true;

    final notFilled = currentItem.stack.count - toInsert.count;
    if (remainder.isNotEmpty) {
      remainder = remainder.grow(notFilled);
    } else if (notFilled > 0) {
      remainder = currentItem.stack.withCount(notFilled);
    }
    currentItem.stack = remainder;
    env.notifyUpdate();
    return true;
  }
  return false;
}
