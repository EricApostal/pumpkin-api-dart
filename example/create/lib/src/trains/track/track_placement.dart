// `TrackPlacement` (pure): the whole algorithm that connects two track points with a straight or a
// curve: which ends belong together, how far the straights extend, whether the curve is allowed,
// what it costs, and the placement of the blocks and block entity connections.
//
// Java -> Dart: [tryConnect] works on the player's inventory snapshot ([TrackPlacementPlayer]);
// the host writes the changed slots back afterwards. The client half of the class (hint outlines,
// overlay, `clientTick`) is not ported.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/byte_buf.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketReader, PacketWriter;
import 'bezier_connection.dart';
import 'i_track_block.dart';
import 'track_block.dart';
import 'track_level.dart';
import 'track_material.dart';
import 'track_paver.dart';
import 'track_shape.dart';

/// `TrackPlacement.ConnectingFrom`: the track end a held track item is connecting from; the value
/// of the data component `create:track_connecting_from`.
final class ConnectingFrom {
  final Pos pos;
  final Vec3 axis;
  final Vec3 normal;
  final Vec3 end;

  const ConnectingFrom(this.pos, this.axis, this.normal, this.end);

  /// `STREAM_CODEC`: the packed block position and three vectors.
  void write(PacketWriter buffer) {
    buffer.writeBlockPos(pos);
    buffer.writeVec3(axis);
    buffer.writeVec3(normal);
    buffer.writeVec3(end);
  }

  static ConnectingFrom read(PacketReader buffer) {
    final pos = buffer.readBlockPos();
    final axis = buffer.readVec3();
    final normal = buffer.readVec3();
    final end = buffer.readVec3();
    return ConnectingFrom(pos, axis, normal, end);
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectingFrom &&
      other.pos == pos &&
      other.axis == axis &&
      other.normal == normal &&
      other.end == end;

  @override
  int get hashCode => Object.hash(pos, axis, normal, end);
}

/// `TrackPlacement.PlacementInfo`.
class PlacementInfo {
  PlacementInfo(this.trackMaterial);

  BezierConnection? curve;
  bool valid = false;
  int end1Extent = 0;
  int end2Extent = 0;
  String? message;

  int requiredTracks = 0;
  bool hasRequiredTracks = false;

  int requiredPavement = 0;
  bool hasRequiredPavement = false;
  final TrackMaterial trackMaterial;

  // for visualisation
  Vec3? end1;
  Vec3? end2;
  Vec3? normal1;
  Vec3? normal2;
  Vec3? axis1;
  Vec3? axis2;
  Pos? pos1;
  Pos? pos2;

  PlacementInfo withMessage(String message) {
    this.message = 'track.$message';
    return this;
  }

  PlacementInfo tooJumbly() {
    curve = null;
    return this;
  }
}

abstract final class TrackPlacement {
  /// `tryConnect(level, player, pos2, state2, stack, girder, maximiseTurn)`: checks the
  /// connection from the stack's `connectingFrom` to ([pos2], [state2]) and, when valid, places
  /// it and takes the items from [player]'s inventory (unless creative).
  static Future<PlacementInfo> tryConnect(
    TrackLevel level,
    TrackPlacementPlayer player,
    Pos pos2,
    BState state2,
    TrackItemStack stack,
    bool girder,
    bool maximiseTurn,
  ) async {
    final lookVec = player.getLookAngle();
    final maxLength = level.maxTrackPlacementLength;

    final info = PlacementInfo(TrackMaterial.fromItem(stack.itemKey));

    final track = TrackBlockRegistry.ofState(state2)!;
    final nearestTrackAxis = track.getNearestTrackAxis(level, pos2, state2, lookVec);
    var axis2 = nearestTrackAxis.getFirst() * (nearestTrackAxis.getSecond() == AxisDirection.positive ? -1 : 1);
    final normal2 = vnorm(track.getUpNormal(level, pos2, state2));
    var normedAxis2 = vnorm(axis2);
    var end2 = track.getCurveStart(level, pos2, state2, axis2);

    final connectingFrom = stack.connectingFrom;
    if (connectingFrom == null) return info.withMessage('original_missing');

    final pos1 = connectingFrom.pos;
    var axis1 = connectingFrom.axis;
    var normedAxis1 = vnorm(axis1);
    var end1 = connectingFrom.end;
    final normal1 = connectingFrom.normal;
    final state1 = level.stateAt(pos1);

    if (pos1 == pos2) return info.withMessage('second_point');
    if (pos1.distSqr(pos2) > maxLength * maxLength) return info.withMessage('too_far').tooJumbly();
    if (!state1.has(trackHasBeProperty)) return info.withMessage('original_missing');
    final tbe2 = level.getTrackBlockEntity(pos2);
    if (tbe2 != null && tbe2.isTilted()) return info.withMessage('turn_start');

    if (axis1.dot(end2 - end1) < 0) {
      axis1 = axis1 * -1;
      normedAxis1 = normedAxis1 * -1;
      end1 = track.getCurveStart(level, pos1, state1, axis1);
    }

    var intersect = VecHelper.intersect(end1, end2, normedAxis1, normedAxis2, Axis.y);
    final parallel = intersect == null;
    var skipCurve = false;

    if ((parallel && normedAxis1.dot(normedAxis2) > 0) || (!parallel && (intersect[0] < 0 || intersect[1] < 0))) {
      axis2 = axis2 * -1;
      normedAxis2 = normedAxis2 * -1;
      end2 = track.getCurveStart(level, pos2, state2, axis2);
    }

    final cross2 = normedAxis2.cross((0.0, 1.0, 0.0));

    final a1 = math.atan2(normedAxis2.z, normedAxis2.x);
    final a2 = math.atan2(normedAxis1.z, normedAxis1.x);
    final angle = a1 - a2;
    final ascend = (end2 - end1).y;
    final absAscend = ascend.abs();
    final slope = normal1 != normal2;

    // S curve or Straight

    var dist = 0.0;

    if (parallel) {
      final sTest = VecHelper.intersect(end1, end2, normedAxis1, cross2, Axis.y);
      if (sTest != null) {
        final t = sTest[0].abs();
        final u = sTest[1].abs();

        skipCurve = mthEqual(u, 0);

        if (!skipCurve && sTest[0] < 0) return info.withMessage('perpendicular').tooJumbly();

        if (skipCurve) {
          dist = VecHelper.getCenterOf(pos1).distanceTo(VecHelper.getCenterOf(pos2));
          info.end1Extent = _round((dist + 1) / axis1.length);
        } else {
          if (!mthEqual(ascend, 0) || normedAxis1.y != 0) return info.withMessage('ascending_s_curve');

          final targetT = u <= 1 ? 3.0 : u * 2;

          if (t < targetT) return info.withMessage('too_sharp');

          // This is for standardising s curve sizes
          if (t > targetT) {
            final correction = ((t - targetT) / axis1.length).toInt();
            info.end1Extent = maximiseTurn ? 0 : correction ~/ 2 + (correction % 2);
            info.end2Extent = maximiseTurn ? 0 : correction ~/ 2;
          }
        }
      }
    }

    // Slope

    if (slope) {
      if (!skipCurve) return info.withMessage('slope_turn');
      if (mthEqual(normal1.dot(normal2), 0)) return info.withMessage('opposing_slopes');
      if ((axis1.y < 0 || axis2.y > 0) && ascend > 0) return info.withMessage('leave_slope_ascending');
      if ((axis1.y > 0 || axis2.y < 0) && ascend < 0) return info.withMessage('leave_slope_descending');

      skipCurve = false;
      info.end1Extent = 0;
      info.end2Extent = 0;

      final plane = mthEqual(axis1.x, 0) ? Axis.x : Axis.z;
      intersect = VecHelper.intersect(end1, end2, normedAxis1, normedAxis2, plane);
      if (intersect == null) return info.withMessage('too_sharp').tooJumbly();
      final dist1 = (intersect[0] / axis1.length).abs();
      final dist2 = (intersect[1] / axis2.length).abs();

      if (dist1 > dist2) info.end1Extent = _round(dist1 - dist2);
      if (dist2 > dist1) info.end2Extent = _round(dist2 - dist1);

      var turnSize = math.min(dist1, dist2);
      if (intersect[0] < 0 || intersect[1] < 0) return info.withMessage('too_sharp').tooJumbly();
      if (turnSize < 2) return info.withMessage('too_sharp');

      // This is for standardising curve sizes
      if (turnSize > 2 && !maximiseTurn) {
        info.end1Extent = (info.end1Extent + (turnSize - 2)).toInt();
        info.end2Extent = (info.end2Extent + (turnSize - 2)).toInt();
        turnSize = 2;
      }
    }

    // Straight ascend

    if (skipCurve && !mthEqual(ascend, 0)) {
      final hDistance = info.end1Extent;
      if (axis1.y == 0 || !mthEqual(absAscend + 1, dist / axis1.length)) {
        if (axis1.y != 0 && axis1.y == -axis2.y) return info.withMessage('ascending_s_curve');

        info.end1Extent = 0;
        final minHDistance = math.max(absAscend < 4 ? absAscend * 4 : absAscend * 3, 6.0) / axis1.length;
        if (hDistance < minHDistance) return info.withMessage('too_steep');
        if (hDistance > minHDistance) {
          final correction = (hDistance - minHDistance).toInt();
          info.end1Extent = maximiseTurn ? 0 : correction ~/ 2 + (correction % 2);
          info.end2Extent = maximiseTurn ? 0 : correction ~/ 2;
        }

        skipCurve = false;
      }
    }

    // Turn

    if (!parallel) {
      final absAngle = AngleHelper.deg(angle).abs();
      if (absAngle < 60 || absAngle > 300) return info.withMessage('turn_90').tooJumbly();

      intersect = VecHelper.intersect(end1, end2, normedAxis1, normedAxis2, Axis.y);
      if (intersect == null) return info.withMessage('too_sharp').tooJumbly();
      final dist1 = intersect[0].abs();
      final dist2 = intersect[1].abs();
      var ex1 = 0.0; // floats
      var ex2 = 0.0;

      if (dist1 > dist2) ex1 = toFloat((dist1 - dist2) / axis1.length);
      if (dist2 > dist1) ex2 = toFloat((dist2 - dist1) / axis2.length);

      var turnSize = math.min(dist1, dist2) - .1;
      final ninety = toFloat(absAngle + toFloat(.25)) % 90 < 1;

      if (intersect[0] < 0 || intersect[1] < 0) return info.withMessage('too_sharp').tooJumbly();

      final minTurnSize = ninety ? 7.0 : 3.25;
      final turnSizeToFitAscend =
          minTurnSize + (ninety ? math.max(0.0, absAscend - 3) * 2 : math.max(0.0, absAscend - 1.5) * 1.5);

      if (turnSize < minTurnSize) return info.withMessage('too_sharp');
      if (turnSize < turnSizeToFitAscend) return info.withMessage('too_steep');

      // This is for standardising curve sizes
      if (!maximiseTurn) {
        ex1 = toFloat(ex1 + (turnSize - turnSizeToFitAscend) / axis1.length);
        ex2 = toFloat(ex2 + (turnSize - turnSizeToFitAscend) / axis2.length);
      }
      info.end1Extent = ex1.floor();
      info.end2Extent = ex2.floor();
      turnSize = turnSizeToFitAscend;
    }

    final offset1 = axis1 * info.end1Extent;
    final offset2 = axis2 * info.end2Extent;
    final targetPos1 = pos1 + posContaining(offset1);
    final targetPos2 = pos2 + posContaining(offset2);

    info.curve = skipCurve
        ? null
        : BezierConnection(
            Couple<Pos>(targetPos1, targetPos2),
            Couple<Vec3>(end1 + offset1, end2 + offset2),
            Couple<Vec3>(normedAxis1, normedAxis2),
            Couple<Vec3>(normal1, normal2),
            true,
            girder,
            TrackMaterial.fromItem(stack.itemKey),
          );

    info.valid = true;

    info.pos1 = pos1;
    info.pos2 = pos2;
    info.axis1 = axis1;
    info.axis2 = axis2;

    await _placeTracks(level, info, state1, state2, targetPos1, targetPos2, true);

    final inventory = player.inventory;
    final offhandItem = inventory.offhand?.copy();
    final shouldPave = offhandItem != null &&
        !offhandItem.isEmpty &&
        level.paveBlockOf(offhandItem.itemKey) != null &&
        !level.isInvalidForTrackPaving(offhandItem.itemKey);
    if (shouldPave) {
      await _paveTracks(level, info, level.paveBlockOf(offhandItem.itemKey)!, true);
      info.hasRequiredPavement = true;
    }

    info.hasRequiredTracks = true;

    if (!player.isCreative()) {
      for (final simulate in Iterate.trueAndFalse) {
        final tracks = info.requiredTracks;
        final pavement = info.requiredPavement;
        var foundTracks = 0;
        var foundPavement = 0;

        final inv = inventory;
        final size = inv.nonEquipmentItems.length;
        for (var j = 0; j <= size + 1; j++) {
          var i = j;
          final offhand = j == size + 1;
          if (j == size) {
            i = inv.selectedSlot;
          } else if (offhand) {
            i = 0;
          } else if (j == inv.selectedSlot) {
            continue;
          }

          final stackInSlot = offhand ? inv.offhand : inv.nonEquipmentItems[i];
          if (stackInSlot == null || stackInSlot.isEmpty) continue;
          final isTrack = TrackBlockRegistry.keys.contains(stackInSlot.itemKey) && stackInSlot.itemKey == stack.itemKey;
          if (!isTrack && (!shouldPave || offhandItem.itemKey != stackInSlot.itemKey)) continue;
          if (isTrack ? foundTracks >= tracks : foundPavement >= pavement) continue;

          final count = stackInSlot.count;

          if (!simulate) {
            final int remainingItems = count - math.min<int>(isTrack ? tracks - foundTracks : pavement - foundPavement, count);
            if (i == inv.selectedSlot) stackInSlot.connectingFrom = null;
            final newItem = stackInSlot.copyWithCount(remainingItems);
            if (offhand) {
              inv.offhand = newItem;
            } else {
              inv.nonEquipmentItems[i] = newItem;
            }
          }

          if (isTrack) {
            foundTracks += count;
          } else {
            foundPavement += count;
          }
        }

        if (simulate && foundTracks < tracks) {
          info.valid = false;
          info.tooJumbly();
          info.hasRequiredTracks = false;
          return info.withMessage('not_enough_tracks');
        }

        if (simulate && foundPavement < pavement) {
          info.valid = false;
          info.tooJumbly();
          info.hasRequiredPavement = false;
          return info.withMessage('not_enough_pavement');
        }
      }
    }

    if (shouldPave) {
      await _paveTracks(level, info, level.paveBlockOf(offhandItem.itemKey)!, false);
    }
    return _placeTracks(level, info, state1, state2, targetPos1, targetPos2, false);
  }

  /// `Math.round(double)` as an int.
  static int _round(double x) => (x + 0.5).floor();

  static Future<void> _paveTracks(TrackLevel level, PlacementInfo info, PaveBlockInfo block, bool simulate) async {
    info.requiredPavement = 0;
    if (block.isEntityBlock || block.collisionEmpty) return;

    final visited = <Pos>{};

    for (final first in Iterate.trueAndFalse) {
      final extent = (first ? info.end1Extent : info.end2Extent) + (info.curve != null ? 1 : 0);
      final axis = first ? info.axis1! : info.axis2!;
      final pavePos = first ? info.pos1! : info.pos2!;
      info.requiredPavement += await TrackPaver.paveStraight(level, pavePos.below, axis, extent, block, simulate, visited);
    }

    if (info.curve != null) info.requiredPavement += await TrackPaver.paveCurve(level, info.curve!, block, simulate, visited);
  }

  /// `BlockHelper.copyProperties(from, to)`.
  static BState copyProperties(BState from, BState to) {
    var result = to;
    for (final e in from.props.entries) {
      if (to.has(e.key)) result = result.setValue(e.key, e.value);
    }
    return result;
  }

  static BState _defaultStateOf(TrackMaterial material) {
    final block = TrackBlockRegistry.of(material.getBlockKey());
    if (block is TrackBlock) return block.defaultState;
    return BState(material.getBlockKey(), {
      trackShapeProperty: 'zo',
      trackHasBeProperty: 'false',
      waterloggedProperty: 'false',
    });
  }

  static Future<PlacementInfo> _placeTracks(
    TrackLevel level,
    PlacementInfo info,
    BState state1,
    BState state2,
    Pos targetPos1,
    Pos targetPos2,
    bool simulate,
  ) async {
    info.requiredTracks = 0;

    // The run of one placement (the straights of both ends and the two end blocks) is collected
    // and written in batches: one host call per phase instead of one per block, which is what a
    // long run used to cost inside a single tick.
    final changes = <(Pos, BState)>[];

    for (final first in Iterate.trueAndFalse) {
      final extent = first ? info.end1Extent : info.end2Extent;
      final axis = first ? info.axis1! : info.axis2!;
      final pos = first ? info.pos1! : info.pos2!;
      var state = first ? state1 : state2;
      if (state.has(trackHasBeProperty) && !simulate) state = withHasBe(state, false);

      switch (trackShapeOf(state)) {
        case TrackShape.te:
        case TrackShape.tw:
          state = withTrackShape(state, TrackShape.xo);
        case TrackShape.tn:
        case TrackShape.ts:
          state = withTrackShape(state, TrackShape.zo);
        default:
          break;
      }

      for (var i = 0; i < (info.curve != null ? extent + 1 : extent); i++) {
        final offset = axis * i;
        final offsetPos = pos + posContaining(offset);
        final stateAtPos = level.stateAt(offsetPos);
        // copy over all shared properties from the shaped state to the correct track material block
        var toPlace = copyProperties(state, _defaultStateOf(info.trackMaterial));

        var canPlace = level.canBeReplaced(offsetPos) || level.hasTag(offsetPos, 'minecraft:flowers');
        if (canPlace) info.requiredTracks++;
        if (simulate) continue;

        final trackAtPos = TrackBlockRegistry.ofState(stateAtPos);
        if (trackAtPos != null) {
          toPlace = trackAtPos.overlay(level, offsetPos, stateAtPos, toPlace);
          canPlace = true;
        }

        if (canPlace) changes.add((offsetPos, withWater(level, toPlace, offsetPos)!));
      }
    }

    // Java writes each block as it goes; the straights are done before the end blocks read
    // their own position, so the batch is flushed here.
    if (changes.isNotEmpty) {
      await level.setBlocks(changes);
      changes.clear();
    }

    if (info.curve == null) return info;

    if (!simulate) {
      final onto = _defaultStateOf(info.trackMaterial);
      var stateAtPos = level.stateAt(targetPos1);
      changes.add((
        targetPos1,
        withHasBe(
          withWater(level, TrackBlockRegistry.isTrack(stateAtPos) ? stateAtPos : copyProperties(state1, onto), targetPos1)!,
          true,
        ),
      ));

      stateAtPos = level.stateAt(targetPos2);
      changes.add((
        targetPos2,
        withHasBe(
          withWater(level, TrackBlockRegistry.isTrack(stateAtPos) ? stateAtPos : copyProperties(state2, onto), targetPos2)!,
          true,
        ),
      ));
      // Flushed before the block entities below are read: `_syncBlockEntity` gives the two end
      // blocks their `turn` block entity with the write.
      await level.setBlocks(changes);
      changes.clear();
    }

    final tte1 = level.getTrackBlockEntity(targetPos1);
    final tte2 = level.getTrackBlockEntity(targetPos2);
    final requiredTracksForTurn = (info.curve!.getSegmentCount() + 1) ~/ 2;

    if (tte1 == null || tte2 == null) {
      info.requiredTracks += requiredTracksForTurn;
      return info;
    }

    if (!tte1.getConnections().containsKey(tte2.getBlockPos())) info.requiredTracks += requiredTracksForTurn;

    if (simulate) return info;

    await tte1.addConnection(info.curve!);
    await tte2.addConnection(info.curve!.secondary());
    await tte1.tilt.tryApplySmoothing();
    await tte2.tilt.tryApplySmoothing();
    return info;
  }
}
