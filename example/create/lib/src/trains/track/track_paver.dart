// `TrackPaver` (pure): the pavement the offhand block makes under placed tracks.
import '../../api/block_state.dart';
import '../../common/common.dart';
import 'bezier_connection.dart';
import 'track_block.dart' show metalGirderKey;
import 'track_level.dart';
import 'track_shape.dart';

abstract final class TrackPaver {
  /// `SlabBlock.TYPE` values.
  static bool _isSlabLike(BState s) => const {'bottom', 'top', 'double'}.contains(s['type']);

  /// `paveStraight(level, startPos, direction, extent, block, simulate, visited)`: the items
  /// needed.
  static Future<int> paveStraight(
    TrackLevel level,
    Pos startPos,
    Vec3 direction,
    int extent,
    PaveBlockInfo block,
    bool simulate,
    Set<Pos> visited,
  ) async {
    var itemsNeeded = 0;

    var defaultBlockState = block.defaultState;
    final slabLike = _isSlabLike(defaultBlockState);
    final wallLike = _isWallLike(block);

    if (slabLike) defaultBlockState = defaultBlockState.setValue('type', 'double');

    if (defaultBlockState.key == metalGirderKey) {
      for (final d in Iterate.horizontalDirections) {
        if (d.unitVec3 == direction) {
          defaultBlockState = defaultBlockState
              .setFlag('top', false)
              .setFlag('bottom', false)
              .setValue('axis', d.axis.serializedName)
              .setFlag(d.axis == Axis.x ? 'x' : 'z', true);
        }
      }
    }

    final toPlaceOn = <Pos>{};
    final start = VecHelper.getCenterOf(startPos);
    final mainNormal = direction.cross((0.0, 1.0, 0.0));
    final normalizedNormal = vnorm(mainNormal);
    final normalizedDirection = vnorm(direction);

    final diagFiller = toFloat(0.45);
    for (var i = 0; i < extent; i++) {
      final offset = direction * i;
      final mainPos = start + offset;
      toPlaceOn.add(posContaining(mainPos + mainNormal));
      toPlaceOn.add(posContaining(mainPos - mainNormal));
      if (wallLike) continue;
      toPlaceOn.add(posContaining(mainPos));
      if (i < extent - 1) {
        for (final x in Iterate.positiveAndNegative) {
          toPlaceOn.add(posContaining(mainPos + normalizedNormal * (x * diagFiller) + normalizedDirection * diagFiller));
        }
      }
      if (i > 0) {
        for (final x in Iterate.positiveAndNegative) {
          toPlaceOn.add(posContaining(mainPos + normalizedNormal * (x * diagFiller) + normalizedDirection * -diagFiller));
        }
      }
    }

    final state = defaultBlockState;
    for (final p in toPlaceOn.toList()) {
      if (!visited.add(p)) continue;
      if (await _placeBlockIfFree(level, p, state, simulate)) itemsNeeded += slabLike ? 2 : 1;
    }
    visited.addAll(toPlaceOn);

    return itemsNeeded;
  }

  /// `paveCurve(level, bc, block, simulate, visited)`: the items needed.
  static Future<int> paveCurve(
    TrackLevel level,
    BezierConnection bc,
    PaveBlockInfo block,
    bool simulate,
    Set<Pos> visited,
  ) async {
    var itemsNeeded = 0;

    var defaultBlockState = block.defaultState;
    final slabLike = _isSlabLike(defaultBlockState);
    if (slabLike) defaultBlockState = defaultBlockState.setValue('type', 'double');
    if (_isWallLike(block)) {
      if (defaultBlockState.key == metalGirderKey) return ((bc.getSegmentCount() + 1) ~/ 2) * 2;
      return 0;
    }

    final yLevels = <Pair<int, int>, double>{};
    final tePosition = bc.bePositions.getFirst();
    final up = (0.0, toFloat(3 / 16), 0.0);
    final end1 = bc.starts.getFirst() - tePosition.toVec3() + up;
    final end2 = bc.starts.getSecond() - tePosition.toVec3() + up;
    final axis1 = bc.axes.getFirst();
    final axis2 = bc.axes.getSecond();

    final handleLength = bc.getHandleLength();

    final finish1 = axis1 * handleLength + end1;
    final finish2 = axis2 * handleLength + end2;

    final faceNormal1 = bc.normals.getFirst();
    final faceNormal2 = bc.normals.getSecond();

    final segCount = bc.getSegmentCount();
    final lut = bc.getStepLUT();

    for (var i = 0; i < segCount; i++) {
      var t = i == segCount ? 1.0 : toFloat(toFloat(i * lut[i]) / segCount);
      t = toFloat(t + toFloat(0.5 / segCount));

      final result = VecHelper.bezier(end1, end2, finish1, finish2, t);
      final derivative = vnorm(VecHelper.bezierDerivative(end1, end2, finish1, finish2, t));
      final faceNormal = faceNormal1 == faceNormal2 ? faceNormal1 : VecHelper.slerp(t, faceNormal1, faceNormal2);
      final normal = vnorm(faceNormal.cross(derivative));
      final below = result + faceNormal * toFloat(-1.125);
      final rail1 = below + normal * toFloat(.97);
      final rail2 = below - normal * toFloat(.97);
      final railMiddle = (rail1 + rail2) * .5;

      for (final vec in [rail1, rail2, railMiddle]) {
        final pos = posContaining(vec);
        final key = Pair<int, int>(pos.x, pos.z);
        if (!yLevels.containsKey(key) || yLevels[key]! > vec.y) yLevels[key] = vec.y;
      }
    }

    for (final entry in yLevels.entries) {
      final yValue = entry.value;
      final floor = yValue.floor();
      final placeSlab = slabLike && yValue - floor >= .5;
      var targetPos = (entry.key.first + tePosition.x, floor + tePosition.y, entry.key.second + tePosition.z);
      if (placeSlab) targetPos = targetPos.above;
      final stateToPlace = placeSlab ? defaultBlockState.setValue('type', 'bottom') : defaultBlockState;
      if (!visited.add(targetPos)) continue;
      if (await _placeBlockIfFree(level, targetPos, stateToPlace, simulate)) itemsNeeded += !placeSlab ? 2 : 1;
      if (placeSlab) {
        if (!visited.add(targetPos.below)) continue;
        final topSlab = stateToPlace.setValue('type', 'top');
        if (await _placeBlockIfFree(level, targetPos.below, topSlab, simulate)) itemsNeeded++;
      }
    }

    return itemsNeeded;
  }

  static bool _isWallLike(PaveBlockInfo block) => block.isWall || block.blockKey == metalGirderKey;

  static Future<bool> _placeBlockIfFree(TrackLevel level, Pos pos, BState state, bool simulate) async {
    final stateAtPos = level.stateAt(pos);
    if (stateAtPos.key != state.key && level.canBeReplaced(pos)) {
      if (!simulate) await level.setBlock(pos, withWater(level, state, pos)!);
      return true;
    }
    return false;
  }
}
