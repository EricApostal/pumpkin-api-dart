// Box shapes for the redstone blocks (`AllShapes` / `VoxelShaper`). A shape is defined
// facing some direction and rotated to the others about the block centre.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/common.dart';

typedef _V = (double, double, double);

/// The point [p] of the block (0 to 1) rotated so that the `up` axis faces [to]
/// (the maps of `Direction.UP` to each direction, a quarter turn about a horizontal axis).
_V _fromUp(_V p, Direction to) {
  final x = p.$1 - 0.5, y = p.$2 - 0.5, z = p.$3 - 0.5;
  final _V r = switch (to) {
    Direction.up => (x, y, z),
    Direction.down => (x, -y, -z),
    Direction.north => (x, z, -y),
    Direction.south => (x, -z, y),
    Direction.east => (y, -x, z),
    Direction.west => (-y, x, z),
  };
  return (r.$1 + 0.5, r.$2 + 0.5, r.$3 + 0.5);
}

/// The inverse of [_fromUp]: maps a point of a shape facing [from] to the `up` facing.
_V _toUp(_V p, Direction from) {
  final x = p.$1 - 0.5, y = p.$2 - 0.5, z = p.$3 - 0.5;
  final _V r = switch (from) {
    Direction.up => (x, y, z),
    Direction.down => (x, -y, -z),
    Direction.north => (x, -z, y),
    Direction.south => (x, z, -y),
    Direction.east => (-y, x, z),
    Direction.west => (y, -x, z),
  };
  return (r.$1 + 0.5, r.$2 + 0.5, r.$3 + 0.5);
}

/// Rotates the point [p] by [turns] clockwise quarter turns about the Y axis.
_V _turnY(_V p, int turns) {
  var x = p.$1 - 0.5, z = p.$3 - 0.5;
  for (var i = 0; i < ((turns % 4) + 4) % 4; i++) {
    final nx = -z, nz = x; // clockwise seen from above: north -> east
    x = nx;
    z = nz;
  }
  return (x + 0.5, p.$2, z + 0.5);
}

BlockBox _normalize(_V a, _V b) => BlockBox(
  a.$1 < b.$1 ? a.$1 : b.$1,
  a.$2 < b.$2 ? a.$2 : b.$2,
  a.$3 < b.$3 ? a.$3 : b.$3,
  a.$1 < b.$1 ? b.$1 : a.$1,
  a.$2 < b.$2 ? b.$2 : a.$2,
  a.$3 < b.$3 ? b.$3 : a.$3,
);

/// Rotates [boxes] (defined facing [from]) to face [to] (`VoxelShaper.forDirectional`).
List<BlockBox> rotateBoxes(List<BlockBox> boxes, Direction from, Direction to) {
  if (from == to) return boxes;
  if (from.isHorizontal && to.isHorizontal) {
    var turns = 0;
    var d = from;
    while (d != to && turns < 4) {
      d = d.clockWise;
      turns++;
    }
    return [
      for (final b in boxes) _normalize(_turnY((b.minX, b.minY, b.minZ), turns), _turnY((b.maxX, b.maxY, b.maxZ), turns)),
    ];
  }
  return [
    for (final b in boxes)
      _normalize(
        _fromUp(_toUp((b.minX, b.minY, b.minZ), from), to),
        _fromUp(_toUp((b.maxX, b.maxY, b.maxZ), from), to),
      ),
  ];
}

/// A box in pixels (16 per block).
BlockBox pixelBox(double x0, double y0, double z0, double x1, double y1, double z1) =>
    BlockBox(x0 / 16, y0 / 16, z0 / 16, x1 / 16, y1 / 16, z1 / 16);

/// `ShapeRule`s for a block with a `facing` property whose shape is defined facing [from].
List<ShapeRule> directionalShapeRules(String property, List<BlockBox> boxes, Direction from, {Iterable<Direction>? directions, bool collision = true}) => [
  for (final d in directions ?? Direction.values)
    ShapeRule(
      when: {property: d.serializedName},
      collisionShape: collision ? BlockShape.boxes(rotateBoxes(boxes, from, d)) : null,
      selectionShape: BlockShape.boxes(rotateBoxes(boxes, from, d)),
    ),
];

/// The vanilla lever shapes (`Shapes.rotateAttachFace(Block.boxZ(6.0, 8.0, 10.0, 16.0))`),
/// selection only: the lever has no collision shape. The wall shape faces north.
List<ShapeRule> leverShapeRules() {
  BlockBox px(double x0, double y0, double z0, double x1, double y1, double z1) =>
      BlockBox(x0 / 16, y0 / 16, z0 / 16, x1 / 16, y1 / 16, z1 / 16);
  BlockShape s(BlockBox b) => BlockShape.boxes([b]);
  final rules = <ShapeRule>[];
  for (final facing in Direction.horizontals) {
    final nsAxis = facing.axis == Axis.z;
    // The floor and ceiling variants are the wall shape turned a quarter about x, so the
    // 2px handle band becomes a 6px band along y: y 0..6 on the floor, y 10..16 on a ceiling.
    rules.add(ShapeRule(when: {'face': 'floor', 'facing': facing.serializedName}, selectionShape: s(nsAxis ? px(5, 0, 4, 11, 6, 12) : px(4, 0, 5, 12, 6, 11))));
    rules.add(ShapeRule(when: {'face': 'ceiling', 'facing': facing.serializedName}, selectionShape: s(nsAxis ? px(5, 10, 4, 11, 16, 12) : px(4, 10, 5, 12, 16, 11))));
    rules.add(ShapeRule(
      when: {'face': 'wall', 'facing': facing.serializedName},
      selectionShape: s(switch (facing) {
        Direction.north => px(5, 4, 10, 11, 12, 16),
        Direction.south => px(5, 4, 0, 11, 12, 6),
        Direction.west => px(10, 4, 5, 16, 12, 11),
        _ => px(0, 4, 5, 6, 12, 11),
      }),
    ));
  }
  return rules;
}
