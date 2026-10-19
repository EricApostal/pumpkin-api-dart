// Value boxes (`ValueBoxTransform` and `ValueSettingsBehaviour`): the interactive slots on the
// faces of the filtering funnels, chutes, tunnels and the hatch. The client draws the box and
// opens the value board; the server decides what a click on the slot does (`testHit`), takes
// the pick of the board (`create:value_settings`) and applies short interactions.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/direction.dart' as d;
import '../../common/vec_helper.dart';

/// `ValueBoxTransform`: where a value box sits on a block (in block local coordinates).
abstract class ValueSlot {
  const ValueSlot();

  /// `getScale()`.
  double get scale => .5;

  /// `getLocalOffset(state)` for the side [side] (ignored by slots that are not sided);
  /// `null` when there is no box.
  Vec3? localOffset(BState state, d.Direction side);

  /// `isSideActive(state, side)`.
  bool isSideActive(BState state, d.Direction side) => true;

  /// `testHit(state, localHit)`.
  bool testHit(BState state, Vec3 localHit, d.Direction side) {
    if (!isSideActive(state, side)) return false;
    final offset = localOffset(state, side);
    if (offset == null) return false;
    return _distance(localHit, offset) < scale / 2;
  }
}

double _distance(Vec3 a, Vec3 b) {
  final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

/// `ValueBoxTransform.Sided`: a box on a face, [southLocation] rotated to the side.
class SidedSlot extends ValueSlot {
  final Vec3 south;
  final bool Function(BState state, d.Direction side)? active;
  final double _scale;

  const SidedSlot(this.south, {this.active, double scale = .5}) : _scale = scale;

  @override
  double get scale => _scale;

  @override
  bool isSideActive(BState state, d.Direction side) => active?.call(state, side) ?? true;

  @override
  Vec3? localOffset(BState state, d.Direction side) {
    var location = south;
    location = VecHelper.rotateCentered(location, AngleHelper.horizontalAngle(side), d.Axis.y);
    location = VecHelper.rotateCentered(location, AngleHelper.verticalAngle(side), d.Axis.x);
    return location;
  }
}

/// A box at a fixed local position.
class FixedSlot extends ValueSlot {
  final Vec3 Function(BState state)? offset;
  final bool Function(BState state, Vec3 localHit)? hit;
  final double _scale;

  const FixedSlot(this.offset, {this.hit, double scale = .5}) : _scale = scale;

  @override
  double get scale => _scale;

  @override
  Vec3? localOffset(BState state, d.Direction side) => offset?.call(state);

  @override
  bool testHit(BState state, Vec3 localHit, d.Direction side) {
    final custom = hit;
    if (custom != null) return custom(state, localHit);
    return super.testHit(state, localHit, side);
  }
}

/// `VecHelper.voxelSpace` for slot positions.
Vec3 voxel(double x, double y, double z) => VecHelper.voxelSpace(x, y, z);

/// `ValueSettingsBehaviour`: a behaviour with a value box.
abstract interface class ValueBox {
  /// `isActive()`.
  bool get isActive;

  /// `getSlotPositioning()`.
  ValueSlot get slot;

  /// `netId()`.
  int get netId;

  /// `acceptsValueSettings()`.
  bool get acceptsValueSettings;

  /// `setValueSettings(player, ValueSettings(row, value), ctrlDown)`.
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown});

  /// `getValueSettings()`.
  (int row, int value) get valueSettings;

  /// The box of the face [side] (`SidedFilteringBehaviour.get(side)`), `null` when the face has
  /// none; plain boxes return themselves.
  ValueBox? forSide(d.Direction side);

  /// `onShortInteract(player, hand, side, hit)`.
  Future<void> onShortInteract(Player player, Hand hand, d.Direction side);
}

/// A block entity with value boxes.
abstract interface class ValueBoxHost {
  List<ValueBox> get valueBoxes;
}
