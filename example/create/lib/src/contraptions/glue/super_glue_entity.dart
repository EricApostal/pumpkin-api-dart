// `SuperGlueEntity` as data: the box of a glue, the block faces it holds together, and its saved
// form. The entity itself is a plugin entity of the host adapter (`GlueEntityHost`).
//
// Java: `content/contraptions/glue/SuperGlueEntity`.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/nbt.dart';
import '../chassis/chassis_logic.dart';
import '../core/level.dart';
import '../core/movement_checks.dart';
import '../core/nbt_map.dart';
import '../core/structure_transform.dart';

import 'dart:math' as math;

/// The block keys that are sticky on a side.
const Set<String> stickyBlocks = {
  'minecraft:slime_block',
  'minecraft:honey_block',
};

/// The bearings, whose facing side is sticky.
const Set<String> stickyBearings = {
  'create:mechanical_bearing',
  'create:windmill_bearing',
  'create:clockwork_bearing',
};

/// `SuperGlueEntity.span`: the box from the lower corner of [start] to the upper corner of [end].
Aabb glueSpan(Pos start, Pos end) =>
    Aabb.between(start.toVec3(), end.toVec3()).expandTowards(1, 1, 1);

/// `SuperGlueEntity.contains`.
bool glueContains(Aabb box, Pos pos) => box.contains(pos.center);

/// `SuperGlueEntity.isGlued(level, blockPos, direction, cached)`: a glue box that contains both the
/// block and its neighbour in [direction].
bool isGlued(
  List<GlueRef> candidates,
  Pos blockPos,
  Direction direction, [
  Set<int>? cached,
]) {
  final target = blockPos.relative(direction);
  if (cached != null) {
    for (final glue in candidates) {
      if (cached.contains(glue.id) &&
          glueContains(glue.box, blockPos) &&
          glueContains(glue.box, target)) {
        return true;
      }
    }
  }
  for (final glue in candidates) {
    if (!glueContains(glue.box, blockPos) || !glueContains(glue.box, target))
      continue;
    cached?.add(glue.id);
    return true;
  }
  return false;
}

/// `SuperGlueEntity.isValidFace`: the block may be glued to the block in [direction].
bool isValidGlueFace(ContraptionLevel level, Pos pos, Direction direction) {
  final state = level.stateAt(pos);
  if (BlockMovementChecks.isBlockAttachedTowards(state, level, pos, direction))
    return true;
  if (!BlockMovementChecks.isMovementNecessary(state, level, pos)) return false;
  if (BlockMovementChecks.isNotSupportive(state, direction, level))
    return false;
  return true;
}

/// `SuperGlueEntity.isSideSticky`.
bool isSideSticky(BState state, Direction direction) {
  if (state.key == 'create:sticky_mechanical_piston' ||
      state.key == 'create:sticker' ||
      state.key == 'create:gantry_carriage' ||
      stickyBearings.contains(state.key)) {
    return state.dir('facing') == direction;
  }
  if (stickyBlocks.contains(state.key)) return true;
  if (state.key == 'create:cart_assembler') return direction == Direction.up;
  if (isChassis(state)) {
    final side = chassisGlueableSide(state, direction);
    return side != null && state.flag(side);
  }
  return false;
}

/// `SuperGlueEntity.collectCropped(level, bb)`: the parts of the glue boxes inside [bb] that are
/// not exactly one block.
List<Aabb> collectCroppedGlue(List<GlueRef> glues, Aabb area) {
  final result = <Aabb>[];
  for (final glue in glues) {
    final box = glue.box;
    final intersect = area.intersect(box);
    if (intersect.xSize * intersect.ySize * intersect.zSize == 0) continue;
    if ((intersect.xSize - 1).abs() < 1.0e-5 &&
        (intersect.ySize - 1).abs() < 1.0e-5 &&
        (intersect.zSize - 1).abs() < 1.0e-5) {
      continue;
    }
    result.add(intersect);
  }
  return result;
}

/// `SuperGlueEntity.writeBoundingBox`.
void writeGlueBox(NbtMap compound, Aabb box) {
  compound.putVec('From', (box.minX, box.minY, box.minZ));
  compound.putVec('To', (box.maxX, box.maxY, box.maxZ));
}

/// `SuperGlueEntity.readBoundingBox`.
Aabb readGlueBox(NbtMap compound) =>
    Aabb.between(compound.getVec('From'), compound.getVec('To'));

/// `SuperGlueEntity.rotate(Rotation)`: a quarter turn swaps the horizontal extents.
Aabb rotateGlueBox(Aabb box, BlockRotation rotation) {
  if (rotation != BlockRotation.clockwise90 &&
      rotation != BlockRotation.counterclockwise90)
    return box;
  return Aabb(box.minZ, box.minY, box.minX, box.maxZ, box.maxY, box.maxX);
}

/// The box of a glue entity after the [transform] (`StructureTransform.applyAabb`).
Aabb transformGlueBox(Aabb box, StructureTransform transform) =>
    transform.applyAabb(box);

/// `Math.max` of the extents of [box].
double glueVolume(Aabb box) =>
    math.max(0, box.xSize) * math.max(0, box.ySize) * math.max(0, box.zSize);

/// The value type of a glue box in a payload (the entity's spawn data).
NbtValue glueBoxValue(Aabb box) =>
    (NbtMap()
          ..putVec('From', (box.minX, box.minY, box.minZ))
          ..putVec('To', (box.maxX, box.maxY, box.maxZ)))
        .toValue();
