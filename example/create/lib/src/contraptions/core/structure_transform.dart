// `StructureTransform` (pure): the rotation (around one axis) and mirroring a contraption applies to
// its blocks and block entities when it is placed back into the world, plus the registries other
// modules use to say how their blocks and block entities transform
// (`MovedBlockTransformerRegistries`, `TransformableBlock`).
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../schematics/state_transform.dart' as vanilla;
import 'nbt_map.dart';

/// How a block transforms with a [StructureTransform] (`BlockTransformer`).
typedef BlockTransformer = BState Function(BState state, StructureTransform transform);

/// How the saved data of a block entity transforms (`BlockEntityTransformer`): changes [nbt] in place.
typedef BlockEntityTransformer = void Function(NbtMap nbt, StructureTransform transform);

/// `MovedBlockTransformerRegistries`: keyed by block key and block entity type key.
abstract final class MovedBlockTransformers {
  static final Map<String, BlockTransformer> blocks = {};
  static final Map<String, BlockEntityTransformer> blockEntities = {};

  /// How the value domain of a block property is looked up: the values the block can have for
  /// [property], `null` when unknown. The host installs one that asks the block registry.
  static Set<String>? Function(String blockKey, String property) domainOf = _guessDomain;

  static Set<String>? _guessDomain(String blockKey, String property) => null;
}

/// Whether the `facing` property of [s] is the six-way `BlockStateProperties.FACING`.
bool _isSixWayFacing(BState s) {
  final f = s['facing'];
  if (f == null) return false;
  final domain = MovedBlockTransformers.domainOf(s.key, 'facing');
  if (domain != null) return domain.contains('up') && domain.contains('down');
  return f == 'up' || f == 'down' || _knownSixWay.contains(s.key);
}

const Set<String> _knownSixWay = {
  'minecraft:piston',
  'minecraft:sticky_piston',
  'minecraft:piston_head',
  'minecraft:dispenser',
  'minecraft:dropper',
  'minecraft:observer',
  'minecraft:end_rod',
  'minecraft:lightning_rod',
  'minecraft:barrel',
  'minecraft:command_block',
  'minecraft:chain_command_block',
  'minecraft:repeating_command_block',
  'minecraft:shulker_box',
  'minecraft:amethyst_cluster',
  'minecraft:large_amethyst_bud',
  'minecraft:medium_amethyst_bud',
  'minecraft:small_amethyst_bud',
};

/// Whether the `axis` property of [s] is the three-way `BlockStateProperties.AXIS`.
bool _isThreeWayAxis(BState s) {
  final a = s['axis'];
  if (a == null) return false;
  final domain = MovedBlockTransformers.domainOf(s.key, 'axis');
  if (domain != null) return domain.contains('y');
  return a == 'y' || !s.key.startsWith('minecraft:nether_portal');
}

/// `StructureTransform`.
final class StructureTransform {
  /// The axis of the rotation, `null` when there is none.
  final Axis? rotationAxis;
  final Pos offset;
  final int angle;
  final BlockRotation rotation;
  final BlockMirror mirror;

  StructureTransform._(this.offset, this.angle, this.rotationAxis, this.rotation, this.mirror);

  /// `new StructureTransform(offset, axis, rotation, mirror)`.
  factory StructureTransform(Pos offset, Axis? axis, BlockRotation rotation, BlockMirror mirror) =>
      StructureTransform._(offset, rotation == BlockRotation.none ? 0 : (4 - rotation.index) * 90, axis, rotation, mirror);

  /// `new StructureTransform(offset, xRotation, yRotation, zRotation)`: angles in degrees,
  /// rounded to quarter turns.
  factory StructureTransform.angles(Pos offset, double xRotation, double yRotation, double zRotation) {
    Axis? axis;
    var angle = 0;
    int quarter(double d) => (d / 90).round() * 90;
    if (xRotation != 0) {
      axis = Axis.x;
      angle = quarter(xRotation);
    }
    if (yRotation != 0) {
      axis = Axis.y;
      angle = quarter(yRotation);
    }
    if (zRotation != 0) {
      axis = Axis.z;
      angle = quarter(zRotation);
    }
    angle = angle.remainder(360);
    if (angle < -90) angle += 360;
    var rotation = BlockRotation.none;
    if (angle == -90 || angle == 270) rotation = BlockRotation.clockwise90;
    if (angle == 90) rotation = BlockRotation.counterclockwise90;
    if (angle == 180) rotation = BlockRotation.clockwise180;
    return StructureTransform._(offset, angle, axis, rotation, BlockMirror.none);
  }

  /// The identity at [offset].
  factory StructureTransform.identity(Pos offset) =>
      StructureTransform._(offset, 0, null, BlockRotation.none, BlockMirror.none);

  /// Reads the `StructureTransform` of the `contraption_disassemble` payload.
  factory StructureTransform.fromWire(Map<String, Object?> f) {
    final axisOrdinal = f['rotationAxis'] as int?;
    final rotationOrdinal = f['rotation'] as int?;
    final mirrorOrdinal = f['mirror'] as int?;
    return StructureTransform._(
      f['offset']! as Pos,
      f['angle']! as int,
      axisOrdinal == null ? null : Axis.values[axisOrdinal.clamp(0, 2)],
      rotationOrdinal == null ? BlockRotation.none : BlockRotation.values[rotationOrdinal.clamp(0, 3)],
      mirrorOrdinal == null ? BlockMirror.none : BlockMirror.values[mirrorOrdinal.clamp(0, 2)],
    );
  }

  /// The fields of the `contraption_disassemble` payload.
  Map<String, Object?> toWire() => {
    'offset': offset,
    'angle': angle,
    'rotationAxis': rotationAxis?.index,
    'rotation': rotation.index,
    'mirror': mirror.index,
  };

  // -- Vectors and positions ----------------------------------------------------------------

  /// `applyWithoutOffsetUncentered`.
  Vec3 applyWithoutOffsetUncentered(Vec3 localVec) {
    var vec = localVec;
    vec = VecHelper.mirror(vec, mirror);
    final axis = rotationAxis;
    if (axis != null) vec = VecHelper.rotate(vec, angle.toDouble(), axis);
    return vec;
  }

  /// `applyWithoutOffset(Vec3)`: mirror then rotate around the block centre.
  Vec3 applyWithoutOffset(Vec3 localVec) {
    var vec = localVec;
    vec = VecHelper.mirrorCentered(vec, mirror);
    final axis = rotationAxis;
    if (axis != null) vec = VecHelper.rotateCentered(vec, angle.toDouble(), axis);
    return vec;
  }

  /// `unapplyWithoutOffset(Vec3)`.
  Vec3 unapplyWithoutOffset(Vec3 globalVec) {
    var vec = globalVec;
    final axis = rotationAxis;
    if (axis != null) vec = VecHelper.rotateCentered(vec, -angle.toDouble(), axis);
    vec = VecHelper.mirrorCentered(vec, mirror);
    return vec;
  }

  /// `apply(Vec3)`.
  Vec3 applyVec(Vec3 localVec) => applyWithoutOffset(localVec) + offset.toVec3();

  /// `applyWithoutOffset(BlockPos)`.
  Pos applyPosWithoutOffset(Pos localPos) => posContaining(applyWithoutOffset(VecHelper.getCenterOf(localPos)));

  /// `apply(BlockPos)`.
  Pos applyPos(Pos localPos) => applyPosWithoutOffset(localPos) + offset;

  /// `unapply(BlockPos)`.
  Pos unapplyPos(Pos globalPos) => unapplyPosWithoutOffset(globalPos - offset);

  /// `unapplyWithoutOffset(BlockPos)`.
  Pos unapplyPosWithoutOffset(Pos globalPos) => posContaining(unapplyWithoutOffset(VecHelper.getCenterOf(globalPos)));

  // -- Facings -------------------------------------------------------------------------------

  /// `mirrorFacing`.
  Direction mirrorFacing(Direction facing) => mirror.mirrorDirection(facing);

  /// `rotateAxis`.
  Axis rotateAxis(Axis axis) => rotateFacing(axis.positive).axis;

  /// `rotateFacing`.
  Direction rotateFacing(Direction facing) {
    var f = facing;
    final axis = rotationAxis;
    if (axis == null) return f;
    for (var i = 0; i < rotation.index; i++) {
      f = f.clockWiseAround(axis);
    }
    return f;
  }

  // -- Blocks --------------------------------------------------------------------------------

  /// `apply(BlockState)`: Create's transformers first, then the generic rules for vanilla states
  /// (`StructureTransform.apply`).
  BState applyState(BState state) {
    final custom = MovedBlockTransformers.blocks[state.key];
    if (custom != null) return custom(state, this);

    var s = vanilla.mirrorState(state, mirror);
    final axis = rotationAxis;
    if (axis == null) return s;

    if (axis == Axis.y) {
      if (s.key == 'minecraft:bell') {
        if (s['attachment'] == 'double_wall') s = s.setValue('attachment', 'single_wall');
        final f = s.dir('facing');
        return f == null ? s : s.setValue('facing', rotation.rotate(f).serializedName);
      }
      return vanilla.rotateState(s, rotation);
    }

    if (s.has('face') && s.has('facing') && (s['face'] == 'floor' || s['face'] == 'wall' || s['face'] == 'ceiling')) {
      return _transformFaceAttached(s, axis);
    }

    final halfTurn = rotation == BlockRotation.clockwise180;
    if (s.key.startsWith('minecraft:') && s.key.endsWith('_stairs')) return _transformStairs(s, axis, halfTurn);

    if (_isSixWayFacing(s)) {
      return s.setValue('facing', rotateFacing(s.dir('facing')!).serializedName);
    } else if (_isThreeWayAxis(s)) {
      final a = s.axisOf('axis');
      if (a != null) return s.setValue('axis', rotateAxis(a).serializedName);
    } else if (halfTurn) {
      if (s.has('facing')) {
        final f = s.dir('facing');
        if (f != null && f.axis == axis) return s;
      }
      s = vanilla.rotateState(s, rotation);
      if (s.has('type') && s['type'] != 'double' && (s['type'] == 'bottom' || s['type'] == 'top')) {
        s = s.setValue('type', s['type'] == 'bottom' ? 'top' : 'bottom');
      }
    }
    return s;
  }

  BState _transformFaceAttached(BState input, Axis axis) {
    var state = input;
    var stateFacing = state.dir('facing') ?? Direction.north;
    var stateFace = state['face']!;
    final z = axis == Axis.z;
    final forcedAxis = z ? Direction.west : Direction.south;
    if (stateFacing.axis == axis && stateFace == 'wall') return state;
    for (var i = 0; i < rotation.index; i++) {
      stateFace = state['face']!;
      stateFacing = state.dir('facing') ?? Direction.north;
      final b = state['face'] == 'ceiling';
      state = state.setValue('facing', (b ? forcedAxis : forcedAxis.opposite).serializedName);
      if (stateFace != 'wall') {
        state = state.setValue('face', 'wall');
        continue;
      }
      if (stateFacing.axisDirection == (z ? AxisDirection.negative : AxisDirection.positive)) {
        state = state.setValue('face', 'floor');
        continue;
      }
      state = state.setValue('face', 'ceiling');
    }
    return state;
  }

  BState _transformStairs(BState input, Axis axis, bool halfTurn) {
    var state = input;
    final facing = state.dir('facing') ?? Direction.north;
    if (facing.axis != axis) {
      for (var i = 0; i < rotation.index; i++) {
        final direction = state.dir('facing') ?? Direction.north;
        final half = state['half'];
        final flip = (direction.axisDirection == AxisDirection.positive) ^ (half == 'bottom') ^ (direction.axis == Axis.z);
        if (flip) {
          state = state.setValue('half', half == 'bottom' ? 'top' : 'bottom');
        } else {
          state = state.setValue('facing', direction.opposite.serializedName);
        }
      }
    } else if (halfTurn) {
      state = state.setValue('half', state['half'] == 'bottom' ? 'top' : 'bottom');
    }
    return state;
  }

  /// `apply(BlockEntity)`: lets the transformer of the block entity type change its saved data.
  void applyBlockEntity(String typeKey, NbtMap nbt) {
    final t = MovedBlockTransformers.blockEntities[typeKey];
    if (t != null) t(nbt, this);
  }

  /// The box of a glue entity after the transform (`new AABB(apply(min), apply(max))`).
  Aabb applyAabb(Aabb box) => Aabb.between(applyVec(box.minPos), applyVec(box.maxPos));

  @override
  String toString() => 'StructureTransform($offset, axis: $rotationAxis, $rotation, $mirror)';
}

/// Rotates the quarter turns of [yaw] degrees around Y the way a contraption entity does.
int quarterTurnsOf(double yaw) => (yaw / 90).round() & 3;

/// The angle between two angles in degrees, wrapped to -180..180.
double wrapDegrees(double a) {
  var x = a % 360;
  if (x >= 180) x -= 360;
  if (x < -180) x += 360;
  return x;
}

/// `Math.atan2` in degrees.
double atan2Degrees(double y, double x) => math.atan2(y, x) * 180 / math.pi;
