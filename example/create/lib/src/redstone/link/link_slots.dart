// `RedstoneLinkFrequencySlot` (pure): where the two frequency items sit on a redstone
// link, to decide which one a right click with an item hit.
import '../../common/common.dart';

/// `getScale()` of the slot.
const double frequencySlotScale = .4975;

/// `RedstoneLinkFrequencySlot.getLocalOffset` for a link facing [facing].
Vec3 frequencySlotOffset(Direction facing, {required bool first}) {
  var location = VecHelper.voxelSpace(8, 3.01, 5.5);

  if (facing.axis.isHorizontal) {
    location = VecHelper.voxelSpace(8, 5.5, 3.01);
    if (first) location = location + (0.0, 5 / 16, 0.0);
    return VecHelper.rotateCentered(location, AngleHelper.horizontalAngle(facing), Axis.y);
  }

  if (first) location = location + (0.0, 0.0, 5 / 16);
  return VecHelper.rotateCentered(location, facing == Direction.down ? 180 : 0, Axis.x);
}

/// `ValueBoxTransform.Dual.testHit`: [localHit] is the hit relative to the block corner.
bool frequencySlotHit(Direction facing, Vec3 localHit, {required bool first}) {
  final offset = frequencySlotOffset(facing, first: first);
  final dx = localHit.$1 - offset.$1, dy = localHit.$2 - offset.$2, dz = localHit.$3 - offset.$3;
  final limit = frequencySlotScale / 3.5;
  return dx * dx + dy * dy + dz * dz < limit * limit;
}
