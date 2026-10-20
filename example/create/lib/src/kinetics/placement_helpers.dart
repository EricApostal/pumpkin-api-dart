// Create's placement assistance for kinetic blocks (`IPlacementHelper`): right
// clicking a shaft with a shaft extends the line, right clicking a cogwheel with a
// cogwheel places the next one diagonally, and so on. Pure: the helpers compute
// where the block goes and how its state is changed; `placement_helper_host.dart`
// places it.
import 'dart:math' as math;

import 'block_defs.dart';
import 'geometry.dart';
import 'node.dart';
import 'placement.dart';

/// `PlacementOffset`.
final class PlacementOffset {
  final bool success;
  final KPos pos;

  /// `stateTransform`: applied to the default state of the placed block.
  final KState Function(KState) transform;

  const PlacementOffset._(this.success, this.pos, this.transform);

  static KState _identity(KState s) => s;

  factory PlacementOffset.fail() => const PlacementOffset._(false, KPos.zero, _identity);

  factory PlacementOffset.at(KPos pos, [KState Function(KState)? transform]) =>
      PlacementOffset._(true, pos, transform ?? _identity);
}

/// What the helpers read of the world.
final class HelperWorld {
  final KState Function(KPos) stateAt;

  /// `BlockState.canBeReplaced()` of the block at a position.
  final bool Function(KPos) canBeReplaced;
  final KineticBlockRegistry blocks;

  /// `equipment.placementAssistRange`.
  final int placementAssistRange;

  const HelperWorld(this.stateAt, this.canBeReplaced, this.blocks, {this.placementAssistRange = 12});
}

// -- Ordering by distance --------------------------------------------------------------

/// `IPlacementHelper.orderedByDistance(pos, hit, include)`: the directions whose unit
/// vector is closest to the hit point (relative to the block centre) first.
List<Dir> orderedByDistance(KPos pos, (double, double, double) hit, [bool Function(Dir)? include]) {
  final cx = hit.$1 - (pos.x + .5);
  final cy = hit.$2 - (pos.y + .5);
  final cz = hit.$3 - (pos.z + .5);
  final entries = <(Dir, double, int)>[];
  var i = 0;
  for (final d in Dir.values) {
    if (include != null && !include(d)) continue;
    final dx = d.dx - cx;
    final dy = d.dy - cy;
    final dz = d.dz - cz;
    entries.add((d, math.sqrt(dx * dx + dy * dy + dz * dz), i++));
  }
  entries.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : a.$3.compareTo(b.$3); // stable
  });
  return [for (final e in entries) e.$1];
}

List<Dir> orderedByDistanceOnlyAxis(KPos pos, (double, double, double) hit, KAxis axis) =>
    orderedByDistance(pos, hit, (d) => d.axis == axis);

List<Dir> orderedByDistanceExceptAxis(
  KPos pos,
  (double, double, double) hit,
  KAxis axis, {
  KAxis? alsoExcept,
  bool Function(Dir)? include,
}) => orderedByDistance(pos, hit, (d) => d.axis != axis && (alsoExcept == null || d.axis != alsoExcept) && (include?.call(d) ?? true));

// -- Pole helper (shafts) ----------------------------------------------------------------

bool _isPoleBlock(KState s) => s.isCreate('shaft') || s.isCreate('cogwheel') || s.isCreate('large_cogwheel') || s.isCreate('powered_shaft');

/// `PoleHelper.getOffset` for `ShaftBlock.PlacementHelper`: extends the line of
/// shafts / cogwheels / powered shafts in the clicked block's axis. [pickType] is
/// `ShaftBlock.pickCorrectShaftType` for the placed state.
PlacementOffset shaftPoleOffset(
  HelperWorld w,
  KPos pos,
  KState state,
  (double, double, double) hit, {
  bool extendo = false,
  KState Function(KState placed, KPos at)? pickType,
}) {
  final axis = state.axisOf('axis') ?? KAxis.y;
  final directions = orderedByDistance(pos, hit, (d) => d.axis == axis);
  for (final dir in directions) {
    final range = w.placementAssistRange + (extendo ? 4 : 0);
    // attachedPoles
    var count = 0;
    var check = pos.relative(dir);
    while (true) {
      // One read per step: the old loop asked the host for the same position twice.
      final state = w.stateAt(check);
      if (!_isPoleBlock(state) || state.axisOf('axis') != dir.axis) break;
      count++;
      check = check.relative(dir);
    }
    final poles = count;
    if (poles >= range) continue;

    final newPos = pos.relative(dir, poles + 1);
    if (w.canBeReplaced(newPos)) {
      return PlacementOffset.at(newPos, (b) {
        final s = b.set('axis', state['axis'] ?? 'y');
        return pickType == null ? s : pickType(s, newPos);
      });
    }
  }
  return PlacementOffset.fail();
}

// -- Cogwheel helpers (CogwheelBlockItem) ----------------------------------------------------------

/// `DiagonalCogHelper.hitOnShaft`: the click hit the shaft in the middle of the cog.
bool hitOnShaft(KState state, KineticBlockDef def, (double, double, double) hit, KPos pos) {
  final axis = def.rotationAxis(state);
  final lx = hit.$1 - pos.x;
  final ly = hit.$2 - pos.y;
  final lz = hit.$3 - pos.z;
  // The SIX_VOXEL_POLE bounds inflated by 0.001: 5/16..11/16 across the axis, anything along it.
  const lo = 5 / 16 - 0.001;
  const hi = 11 / 16 + 0.001;
  bool across(double v) => v >= lo && v <= hi;
  return switch (axis) {
    KAxis.x => across(ly) && across(lz),
    KAxis.y => across(lx) && across(lz),
    KAxis.z => across(lx) && across(ly),
  };
}

PlacementOffset _diagonalCog(HelperWorld w, KPos pos, KState state, KineticBlockDef def, (double, double, double) hit) {
  final axis = def.rotationAxis(state);
  final closest = orderedByDistanceExceptAxis(pos, hit, axis).first;
  final directions = orderedByDistanceExceptAxis(pos, hit, axis, include: (d) => d.axis != closest.axis);
  for (final dir in directions) {
    final newPos = pos.relative(dir).relative(closest);
    if (!w.canBeReplaced(newPos)) continue;
    if (!isValidCogwheelPosition(def.isLargeCog, w.stateAt, w.blocks, newPos, axis)) continue;
    return PlacementOffset.at(newPos, (s) => s.set('axis', axis.name));
  }
  return PlacementOffset.fail();
}

/// `CogwheelBlockItem.SmallCogHelper.getOffset`.
PlacementOffset smallCogOffset(HelperWorld w, KPos pos, KState state, (double, double, double) hit) {
  final def = w.blocks.defFor(state);
  if (def == null || !(def.isSmallCog || def.isLargeCog)) return PlacementOffset.fail();
  if (hitOnShaft(state, def, hit, pos)) return PlacementOffset.fail();

  if (!def.isLargeCog) {
    final axis = def.rotationAxis(state);
    final directions = orderedByDistanceExceptAxis(pos, hit, axis);
    for (final dir in directions) {
      final newPos = pos.relative(dir);
      if (!isValidCogwheelPosition(false, w.stateAt, w.blocks, newPos, axis)) continue;
      if (!w.canBeReplaced(newPos)) continue;
      return PlacementOffset.at(newPos, (s) => s.set('axis', axis.name));
    }
    return PlacementOffset.fail();
  }
  return _diagonalCog(w, pos, state, def, hit);
}

/// `CogwheelBlockItem.LargeCogHelper.getOffset`.
PlacementOffset largeCogOffset(HelperWorld w, KPos pos, KState state, (double, double, double) hit) {
  final def = w.blocks.defFor(state);
  if (def == null || !(def.isSmallCog || def.isLargeCog)) return PlacementOffset.fail();
  if (hitOnShaft(state, def, hit, pos)) return PlacementOffset.fail();

  if (def.isLargeCog) {
    final axis = def.rotationAxis(state);
    final side = orderedByDistanceOnlyAxis(pos, hit, axis).first;
    final directions = orderedByDistanceExceptAxis(pos, hit, axis);
    for (final dir in directions) {
      final newPos = pos.relative(dir).relative(side);
      if (!isValidCogwheelPosition(true, w.stateAt, w.blocks, newPos, dir.axis)) continue;
      if (!w.canBeReplaced(newPos)) continue;
      return PlacementOffset.at(newPos, (s) => s.set('axis', dir.axis.name));
    }
    return PlacementOffset.fail();
  }
  return _diagonalCog(w, pos, state, def, hit);
}

/// The axis an integrated cog (a cog that is part of another block) turns on.
KAxis _integratedAxis(KState state) {
  final facing = state.dirOf('facing');
  if (facing != null) return facing.axis;
  return state.axisOf('axis') ?? KAxis.y;
}

/// `IntegratedSmallCogHelper` / `IntegratedLargeCogHelper.getOffset`: [face] is the
/// clicked face.
PlacementOffset integratedCogOffset(
  HelperWorld w,
  KPos pos,
  KState state,
  Dir face,
  (double, double, double) hit, {
  required bool large,
}) {
  final def = w.blocks.defFor(state);
  if (def == null || def.isDedicatedCogWheel || !def.isSmallCog) return PlacementOffset.fail();
  final newAxis = _integratedAxis(state);
  if (face.axis == newAxis) return PlacementOffset.fail();

  final directions = large
      ? orderedByDistanceExceptAxis(pos, hit, face.axis, alsoExcept: newAxis)
      : orderedByDistanceExceptAxis(pos, hit, newAxis);

  for (final d in directions) {
    final newPos = large ? pos.relative(face).relative(d) : pos.relative(d);
    if (!w.canBeReplaced(newPos)) continue;
    if (!isValidCogwheelPosition(false, w.stateAt, w.blocks, newPos, newAxis)) return PlacementOffset.fail();
    return PlacementOffset.at(newPos, (s) => s.set('axis', newAxis.name));
  }
  return PlacementOffset.fail();
}

/// What `CogwheelBlockItem.onItemUseFirst` does: the helper for the clicked block, or
/// a failed offset.
PlacementOffset cogwheelItemOffset(
  HelperWorld w,
  KPos pos,
  KState state,
  Dir face,
  (double, double, double) hit, {
  required bool large,
}) {
  final def = w.blocks.defFor(state);
  if (def == null) return PlacementOffset.fail();
  if (def.isSmallCog || def.isLargeCog) {
    final o = large ? largeCogOffset(w, pos, state, hit) : smallCogOffset(w, pos, state, hit);
    if (o.success) return o;
  }
  return integratedCogOffset(w, pos, state, face, hit, large: large);
}

// -- Speed controller and steam engine ---------------------------------------------------------

/// `SpeedControllerBlock.PlacementHelper`: a large cogwheel on top.
PlacementOffset speedControllerCogOffset(HelperWorld w, KPos pos, KState state) {
  final newPos = pos.above();
  if (!w.canBeReplaced(newPos)) return PlacementOffset.fail();

  final newAxis = state.axisOf('axis') == KAxis.x ? KAxis.z : KAxis.x;
  if (!isValidCogwheelPosition(true, w.stateAt, w.blocks, newPos, newAxis)) return PlacementOffset.fail();

  return PlacementOffset.at(newPos, (s) => s.set('axis', newAxis.name));
}

/// `SteamEngineBlock.PlacementHelper`: the shaft in front of the engine, its axis
/// chosen by where the player looks ([lookOrder] is `Direction.orderedByNearest`).
PlacementOffset steamEngineShaftOffset(
  HelperWorld w,
  KPos pos,
  KState engine,
  List<Dir> lookOrder,
  bool Function(KState engine, KState shaft) isShaftValid,
  KPos Function(KState engine, KPos pos) shaftPos,
) {
  final sp = shaftPos(engine, pos);
  var shaft = const KState('create:shaft', {'axis': 'y', 'waterlogged': 'false'});
  for (final direction in lookOrder) {
    shaft = shaft.set('axis', direction.axis.name);
    if (isShaftValid(engine, shaft)) break;
  }
  if (!w.canBeReplaced(sp)) return PlacementOffset.fail();
  final axis = shaft['axis']!;
  return PlacementOffset.at(sp, (s) => s.set('axis', axis));
}
