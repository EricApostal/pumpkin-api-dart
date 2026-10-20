// The shapes of the pipe-like fluid blocks (pure): the vanilla `PipeBlock` arms of
// `FluidPipeBlock`, `AxisPipeBlock` (glass), `SmartFluidPipeBlock` and `FluidValveBlock`, plus the
// `AllShapes` entries they use. The shapes are `ShapeRule`s of the block state, so the host answers
// them from the registration without a plugin callback.
//
// The pipe width is what matters: MC 26.3's `PipeBlock(float size, ...)` takes a width in voxels
// (`Block.cube(size)` -> a `size`-voxel box), not a fraction of the block, so `FluidPipeBlock`
// passes `8` and every arm is 8 voxels wide. A hairline pipe (a `4 / 16f` width) leaves a
// 0.25-voxel core, which a ray almost never hits: the selection outline never appears and the
// block cannot be broken.
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show BlockBox, BlockShape, BoxesShape, EmptyShape, FullCubeShape, ShapeRule;

import '../api/block_state.dart' show BState;
import '../common/direction.dart';
import '../conveyance/shapes.dart' show Shape, VoxelShaper, box16;
import 'pipe_blocks.dart';

/// `Block.cube(8)`: the 8-voxel core of a pipe.
const BlockBox _pipeCore = BlockBox(4 / 16, 4 / 16, 4 / 16, 12 / 16, 12 / 16, 12 / 16);

/// `Shapes.rotateAll(Block.boxZ(8, 0, 8))`: the 8-voxel arm of a pipe towards a direction.
const Map<Direction, BlockBox> _pipeArms = {
  Direction.down: BlockBox(4 / 16, 0, 4 / 16, 12 / 16, 8 / 16, 12 / 16),
  Direction.up: BlockBox(4 / 16, 8 / 16, 4 / 16, 12 / 16, 1, 12 / 16),
  Direction.north: BlockBox(4 / 16, 4 / 16, 0, 12 / 16, 12 / 16, 8 / 16),
  Direction.south: BlockBox(4 / 16, 4 / 16, 8 / 16, 12 / 16, 12 / 16, 1),
  Direction.west: BlockBox(0, 4 / 16, 4 / 16, 8 / 16, 12 / 16, 12 / 16),
  Direction.east: BlockBox(8 / 16, 4 / 16, 4 / 16, 1, 12 / 16, 12 / 16),
};

/// `PipeBlock.PROPERTY_BY_DIRECTION`: the six connection properties of a pipe.
const List<Direction> _pipeSides = [
  Direction.down,
  Direction.up,
  Direction.north,
  Direction.south,
  Direction.west,
  Direction.east,
];

/// `AllShapes.EIGHT_VOXEL_POLE` (`AxisPipeBlock.getShape`, the glass pipe).
final VoxelShaper _eightVoxelPole = VoxelShaper.forAxis([
  box16(4, 0, 4, 12, 16, 12),
]);

/// `AllShapes.FLUID_VALVE`.
final VoxelShaper _fluidValve = VoxelShaper.forAxis([
  box16(3, 0, 3, 13, 16, 13),
  box16(2, 2, 2, 14, 14, 14),
]);

/// `AllShapes.SMART_FLUID_PIPE_FLOOR`.
final VoxelShaper _smartPipeFloor = VoxelShaper.forHorizontal([
  box16(4, 4, 0, 12, 12, 16),
  box16(3, 3, 3, 13, 13, 13),
  box16(5, 13, 3, 11, 14, 11),
  box16(5, 14, 4, 11, 15, 10),
  box16(5, 15, 5, 11, 16, 9),
  box16(5, 16, 6, 11, 17, 8),
], Direction.south);

/// `AllShapes.SMART_FLUID_PIPE_WALL`.
final VoxelShaper _smartPipeWall = VoxelShaper.forHorizontal([
  box16(4, 0, 4, 12, 16, 12),
  box16(3, 3, 3, 13, 13, 13),
  box16(5, 5, 13, 11, 13, 14),
  box16(5, 6, 14, 11, 12, 15),
  box16(5, 7, 15, 11, 11, 16),
  box16(5, 8, 16, 11, 10, 17),
], Direction.south);

/// `AllShapes.SMART_FLUID_PIPE_CEILING`.
final VoxelShaper _smartPipeCeiling = VoxelShaper.forHorizontal([
  box16(4, 4, 0, 12, 12, 16),
  box16(3, 3, 3, 13, 13, 13),
  box16(5, 2, 3, 11, 3, 11),
  box16(5, 1, 4, 11, 2, 10),
  box16(5, 0, 5, 11, 1, 9),
  box16(5, -1, 6, 11, 0, 8),
], Direction.south);

/// `AllShapes.PUMP` (`PumpBlock.getShape`): a 12x16x12 box along `facing`.
final VoxelShaper _pump = VoxelShaper.forDirectional([
  box16(2, 0, 2, 14, 16, 14),
]);

/// `PumpBlock.getShape`: `AllShapes.PUMP.get(state.getValue(FACING))`.
List<ShapeRule> pumpShapeRules() => [
  for (final facing in Direction.values)
    _rule({'facing': facing.serializedName}, _pump.get(facing)),
];

/// A rule that gives matching states the same collision and selection [shape].
ShapeRule _rule(Map<String, String> when, Shape shape) {
  final boxes = BlockShape.boxes(shape);
  return ShapeRule(when: when, collisionShape: boxes, selectionShape: boxes);
}

/// `PipeBlock.makeShapes`: the core plus the arm of every open side.
Shape _pipeShape(Set<Direction> open) => [
  _pipeCore,
  for (final side in _pipeSides)
    if (open.contains(side)) _pipeArms[side]!,
];

/// `FluidPipeBlock.getShape` for every combination of its six connection properties (the
/// waterlogged property does not change the shape).
List<ShapeRule> fluidPipeShapeRules() => [
  for (var mask = 0; mask < 1 << _pipeSides.length; mask++)
    _rule(
      {
        for (var i = 0; i < _pipeSides.length; i++)
          _pipeSides[i].serializedName: (mask & (1 << i)) != 0 ? 'true' : 'false',
      },
      _pipeShape({
        for (var i = 0; i < _pipeSides.length; i++)
          if (mask & (1 << i) != 0) _pipeSides[i],
      }),
    ),
];

/// `AxisPipeBlock.getShape` (the glass pipe): a pole along the `axis` property.
List<ShapeRule> glassPipeShapeRules() => [
  for (final axis in Axis.values)
    _rule({'axis': axis.serializedName}, _eightVoxelPole.getAxis(axis)),
];

/// `SmartFluidPipeBlock.getShape`: the `face` picks the shaper, `facing` the rotation.
List<ShapeRule> smartPipeShapeRules() => [
  for (final face in const ['floor', 'wall', 'ceiling'])
    for (final facing in Direction.horizontals)
      _rule(
        {'face': face, 'facing': facing.serializedName},
        switch (face) {
          'wall' => _smartPipeWall,
          'ceiling' => _smartPipeCeiling,
          _ => _smartPipeFloor,
        }.get(facing),
      ),
];

/// `FluidValveBlock.getShape`: `AllShapes.FLUID_VALVE` along the axis the valve passes fluid on.
List<ShapeRule> valveShapeRules() => [
  for (final facing in Direction.values)
    for (final alongFirst in const [true, false])
      _rule(
        {
          'facing': facing.serializedName,
          'axis_along_first': alongFirst ? 'true' : 'false',
        },
        _fluidValve.getAxis(
          PipeBlocks.valvePipeAxis(
            BState(PipeKeys.valve, {
              'facing': facing.serializedName,
              'axis_along_first': alongFirst ? 'true' : 'false',
            }),
          ),
        ),
      ),
];

/// The shapes a pipe-like block registers: the base shapes (the states no rule matches, and the
/// fallback of the host) and the rules of the states.
final class PipeShapeSpec {
  final BlockShape collisionShape;
  final BlockShape selectionShape;
  final List<ShapeRule> shapeRules;

  const PipeShapeSpec({
    required this.collisionShape,
    required this.selectionShape,
    required this.shapeRules,
  });
}

/// The shape registration of the pipe-like block [key], `null` for any other block.
///
/// `EncasedPipeBlock` extends `Block` without a `getShape` override, so the encased pipe keeps the
/// full cube of `Block.getShape` and needs no rules.
PipeShapeSpec? pipeShapeSpec(String key) => switch (key) {
  PipeKeys.fluidPipe => PipeShapeSpec(
    collisionShape: BlockShape.boxes([_pipeCore]),
    selectionShape: BlockShape.boxes([_pipeCore]),
    shapeRules: fluidPipeShapeRules(),
  ),
  PipeKeys.glassPipe => PipeShapeSpec(
    collisionShape: BlockShape.boxes(_eightVoxelPole.getAxis(Axis.y)),
    selectionShape: BlockShape.boxes(_eightVoxelPole.getAxis(Axis.y)),
    shapeRules: glassPipeShapeRules(),
  ),
  PipeKeys.smartPipe => PipeShapeSpec(
    collisionShape: BlockShape.boxes(_smartPipeFloor.get(Direction.north)),
    selectionShape: BlockShape.boxes(_smartPipeFloor.get(Direction.north)),
    shapeRules: smartPipeShapeRules(),
  ),
  PipeKeys.valve => PipeShapeSpec(
    collisionShape: BlockShape.boxes(_fluidValve.getAxis(Axis.y)),
    selectionShape: BlockShape.boxes(_fluidValve.getAxis(Axis.y)),
    shapeRules: valveShapeRules(),
  ),
  PipeKeys.pump => PipeShapeSpec(
    collisionShape: BlockShape.boxes(_pump.get(Direction.north)),
    selectionShape: BlockShape.boxes(_pump.get(Direction.north)),
    shapeRules: pumpShapeRules(),
  ),
  PipeKeys.encasedPipe => const PipeShapeSpec(
    collisionShape: BlockShape.fullCube,
    selectionShape: BlockShape.fullCube,
    shapeRules: [],
  ),
  _ => null,
};

/// The shape of [state] by the rules of [spec] (the host's `shape_definition`: the first rule that
/// matches and sets the shape, else the base shape).
BlockShape shapeOf(PipeShapeSpec spec, Map<String, String> state, {bool selection = true}) {
  for (final rule in spec.shapeRules) {
    final matches = rule.when.entries.every((e) => state[e.key] == e.value);
    if (!matches) continue;
    final shape = selection ? rule.selectionShape : rule.collisionShape;
    if (shape != null) return shape;
  }
  return selection ? spec.selectionShape : spec.collisionShape;
}

/// The boxes of [shape] in block units (`Shapes.empty()` is no box).
List<BlockBox> boxesOf(BlockShape shape) => switch (shape) {
  EmptyShape() => const [],
  FullCubeShape() => const [BlockBox.unit],
  BoxesShape(:final boxes) => boxes,
};
