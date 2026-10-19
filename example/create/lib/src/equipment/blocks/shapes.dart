// Block shapes of the equipment blocks (`AllShapes.TOOLBOX`, `BACKTANK`, `BELL_*`,
// `CLIPBOARD_*`) as shape rules per state. Pure apart from the `pumpkin_api_core` shape model.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../model/dir.dart';

/// A box in 16ths of a block.
typedef Box16 = (double, double, double, double, double, double);

BlockBox _unit(Box16 b) => BlockBox(b.$1 / 16, b.$2 / 16, b.$3 / 16, b.$4 / 16, b.$5 / 16, b.$6 / 16);

/// Rotates [b] clockwise (seen from above) by 90 degrees about the block centre:
/// (x, z) -> (1 - z, x), so north goes to east.
BlockBox rotateCw(BlockBox b) => BlockBox(1 - b.maxZ, b.minY, b.minX, 1 - b.minZ, b.maxY, b.maxX);

/// The quarter turns clockwise from north to [d] (horizontals).
int _turnsFromNorth(Dir d) => switch (d) {
  Dir.north => 0,
  Dir.east => 1,
  Dir.south => 2,
  Dir.west => 3,
  _ => 0,
};

/// `VoxelShaper.forHorizontal(base)`: the boxes for each horizontal facing, given for [base].
Map<Dir, List<BlockBox>> forHorizontal(List<Box16> boxes, {Dir base = Dir.north}) {
  final baseBoxes = [for (final b in boxes) _unit(b)];
  final result = <Dir, List<BlockBox>>{};
  for (final d in const [Dir.north, Dir.south, Dir.west, Dir.east]) {
    var turns = _turnsFromNorth(d) - _turnsFromNorth(base);
    turns = (turns % 4 + 4) % 4;
    var out = baseBoxes;
    for (var i = 0; i < turns; i++) {
      out = [for (final b in out) rotateCw(b)];
    }
    result[d] = out;
  }
  return result;
}

/// Shape rules for each horizontal `facing` value, with [extra] properties that must match too.
List<ShapeRule> horizontalRules(
  List<Box16> boxes, {
  Dir base = Dir.north,
  String property = 'facing',
  Map<String, String> extra = const {},
}) {
  final byDir = forHorizontal(boxes, base: base);
  return [
    for (final e in byDir.entries)
      ShapeRule(
        when: {property: e.key.name, ...extra},
        collisionShape: BlockShape.boxes(e.value),
        selectionShape: BlockShape.boxes(e.value),
      ),
  ];
}

/// `AllShapes.TOOLBOX`.
const List<Box16> toolboxBoxes = [(1, 0, 4, 15, 9, 12)];

/// `AllShapes.BACKTANK`: the tank and the six voxel pole.
List<BlockBox> backtankBoxes() => [_unit((3, 0, 3, 13, 12, 13)), _unit((5, 0, 5, 11, 16, 11))];

const List<Box16> _bellCore = [(3, 1, 3, 13, 13, 13)];

/// `AllShapes.BELL_FLOOR / WALL / DOUBLE_WALL / CEILING` for each `attachment` and `facing`.
List<ShapeRule> bellRules() => [
  ...horizontalRules([(0, 0, 5, 16, 11, 11), ..._bellCore], base: Dir.south, extra: {'attachment': 'floor'}),
  ...horizontalRules([(5, 5, 8, 11, 11, 16), ..._bellCore], base: Dir.south, extra: {'attachment': 'single_wall'}),
  ...horizontalRules([(5, 5, 0, 11, 11, 16), ..._bellCore], base: Dir.south, extra: {'attachment': 'double_wall'}),
  ...horizontalRules([(0, 5, 5, 16, 16, 11), ..._bellCore], base: Dir.south, extra: {'attachment': 'ceiling'}),
];

/// `AllShapes.CLIPBOARD_FLOOR / CEILING / WALL` for each `face` and `facing`.
List<ShapeRule> clipboardRules() => [
  ...horizontalRules([(3, 0, 1, 13, 1, 15)], base: Dir.south, extra: {'face': 'floor'}),
  ...horizontalRules([(3, 15, 1, 13, 16, 15)], base: Dir.south, extra: {'face': 'ceiling'}),
  ...horizontalRules([(3, 1, 0, 13, 15, 1)], base: Dir.south, extra: {'face': 'wall'}),
];
