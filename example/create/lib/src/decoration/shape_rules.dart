// The per-state shapes of the decoration blocks as host shape rules (pure): at most 64 rules
// per block, first match wins per shape. The neighbour dependent ones (walls) use the dynamic
// shape hook instead.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../common/direction.dart' as d;
import 'shapes.dart';
import 'whistle.dart';

BlockShape _boxes(Shape s) => s.isEmpty ? BlockShape.empty : BlockShape.boxes(s);

/// `StairBlock.getShape` as shape rules: 40 states (facing, half, shape).
List<ShapeRule> stairShapeRules() => [
  for (final half in const ['bottom', 'top'])
    for (final shape in const ['straight', 'inner_left', 'inner_right', 'outer_left', 'outer_right'])
      for (final facing in d.Direction.planeHorizontal)
        ShapeRule(
          when: {'half': half, 'shape': shape, 'facing': facing.serializedName},
          collisionShape: _boxes(stairShape(half, shape, facing)),
          selectionShape: _boxes(stairShape(half, shape, facing)),
        ),
];

/// `SlabBlock.getShape`: top and bottom (the double slab is the full block default).
List<ShapeRule> slabShapeRules() => [
  for (final type in const ['top', 'bottom'])
    ShapeRule(
      when: {'type': type},
      collisionShape: _boxes(slabShape(type)),
      selectionShape: _boxes(slabShape(type)),
    ),
];

/// `CrossCollisionBlock` shapes for panes and bars: 16 combinations of the four arms.
List<ShapeRule> paneShapeRules() => [
  for (var mask = 0; mask < 16; mask++)
    ShapeRule(
      when: {
        'north': (mask & 1) != 0 ? 'true' : 'false',
        'east': (mask & 2) != 0 ? 'true' : 'false',
        'south': (mask & 4) != 0 ? 'true' : 'false',
        'west': (mask & 8) != 0 ? 'true' : 'false',
      },
      collisionShape: _boxes(crossShape({
        d.Direction.north: (mask & 1) != 0,
        d.Direction.east: (mask & 2) != 0,
        d.Direction.south: (mask & 4) != 0,
        d.Direction.west: (mask & 8) != 0,
      })),
      selectionShape: _boxes(crossShape({
        d.Direction.north: (mask & 1) != 0,
        d.Direction.east: (mask & 2) != 0,
        d.Direction.south: (mask & 4) != 0,
        d.Direction.west: (mask & 8) != 0,
      })),
    ),
];

List<ShapeRule> ladderShapeRules() => [
  for (final f in d.Direction.planeHorizontal)
    ShapeRule(
      when: {'facing': f.serializedName},
      collisionShape: _boxes(ladderShapes[f]!),
      selectionShape: _boxes(ladderShapes[f]!),
    ),
];

List<ShapeRule> scaffoldingShapeRules() => [
  ShapeRule(
    when: const {'bottom': 'true'},
    collisionShape: _boxes(scaffoldHalf),
    selectionShape: _boxes(scaffoldHalf),
  ),
  // Not on the floor: `SHAPE_STABLE` (the top slab) to stand on, the framed outline to look at.
  ShapeRule(
    when: const {'bottom': 'false'},
    collisionShape: _boxes([box16(0, 14, 0, 16, 16, 16)]),
    selectionShape: _boxes(scaffoldFull),
  ),
];

List<ShapeRule> trapdoorShapeRules() => [
  for (final facing in d.Direction.planeHorizontal)
    for (final half in const ['top', 'bottom'])
      for (final open in const [true, false])
        ShapeRule(
          when: {'facing': facing.serializedName, 'half': half, 'open': '$open'},
          collisionShape: _boxes(trapdoorShape(facing, half, open)),
          selectionShape: _boxes(trapdoorShape(facing, half, open)),
        ),
];

/// `GirderBlock.getShape`: cross, beam along x, beam along z, or the pole (the default shape).
List<ShapeRule> girderShapeRules() => [
  ShapeRule(
    when: const {'x': 'true', 'z': 'true'},
    collisionShape: _boxes(girderCross),
    selectionShape: _boxes(girderCross),
  ),
  ShapeRule(
    when: const {'x': 'true'},
    collisionShape: _boxes(girderBeam.getAxis(d.Axis.x)),
    selectionShape: _boxes(girderBeam.getAxis(d.Axis.x)),
  ),
  ShapeRule(
    when: const {'z': 'true'},
    collisionShape: _boxes(girderBeam.getAxis(d.Axis.z)),
    selectionShape: _boxes(girderBeam.getAxis(d.Axis.z)),
  ),
];

BlockShape girderPoleShape() => _boxes(eightVoxelPole.getAxis(d.Axis.y));

/// `GirderEncasedShaftBlock.getShape` per horizontal axis.
List<ShapeRule> girderEncasedShapeRules() => [
  for (final axis in const [d.Axis.x, d.Axis.z])
    ShapeRule(
      when: {'axis': axis.serializedName},
      collisionShape: _boxes(girderBeamShaft.getAxis(axis)),
      selectionShape: _boxes(girderBeamShaft.getAxis(axis)),
    ),
];

/// `AllShapes.CASING_3PX` per facing.
List<ShapeRule> copycatPanelShapeRules() => [
  for (final f in d.Direction.values)
    ShapeRule(
      when: {'facing': f.serializedName},
      collisionShape: _boxes(casing3px.get(f)),
      selectionShape: _boxes(casing3px.get(f)),
    ),
];

/// `AllShapes.STEP_BOTTOM` / `STEP_TOP` per facing.
List<ShapeRule> copycatStepShapeRules() => [
  for (final half in const ['bottom', 'top'])
    for (final f in d.Direction.planeHorizontal)
      ShapeRule(
        when: {'half': half, 'facing': f.serializedName},
        collisionShape: _boxes((half == 'bottom' ? stepBottom : stepTop).get(f)),
        selectionShape: _boxes((half == 'bottom' ? stepBottom : stepTop).get(f)),
      ),
];

/// `SlidingDoorBlock.getShape`: the vanilla panel while closed and visible, the slid-aside shape
/// otherwise. 4 + 8 rules.
List<ShapeRule> slidingDoorShapeRules({required bool folds}) => [
  for (final f in d.Direction.planeHorizontal)
    ShapeRule(
      when: {'open': 'false', 'visible': 'true', 'facing': f.serializedName},
      collisionShape: _boxes(doorShape(f, false, false)),
      selectionShape: _boxes(doorShape(f, false, false)),
    ),
  for (final f in d.Direction.planeHorizontal)
    for (final hinge in const ['left', 'right'])
      ShapeRule(
        when: {'facing': f.serializedName, 'hinge': hinge},
        collisionShape: _boxes(slidingDoorShape(f, hinge == 'right', folds)),
        selectionShape: _boxes(slidingDoorShape(f, hinge == 'right', folds)),
      ),
];

/// `AllShapes.PLACARD.get(getConnectedDirection(state))`: one rule per connected direction.
List<ShapeRule> placardShapeRules() => [
  for (final face in const ['floor', 'ceiling'])
    ShapeRule(
      when: {'face': face},
      collisionShape: _boxes(placard.get(face == 'floor' ? d.Direction.up : d.Direction.down)),
      selectionShape: _boxes(placard.get(face == 'floor' ? d.Direction.up : d.Direction.down)),
    ),
  for (final f in d.Direction.planeHorizontal)
    ShapeRule(
      when: {'face': 'wall', 'facing': f.serializedName},
      collisionShape: _boxes(placard.get(f)),
      selectionShape: _boxes(placard.get(f)),
    ),
];

/// `WhistleBlock.getShape`: floor or wall variants per size.
List<ShapeRule> whistleShapeRules() => [
  for (final size in whistleSizes) ...[
    ShapeRule(
      when: {'wall': 'false', 'size': size},
      collisionShape: _boxes(whistleFloor[size]!),
      selectionShape: _boxes(whistleFloor[size]!),
    ),
    for (final f in d.Direction.planeHorizontal)
      ShapeRule(
        when: {'wall': 'true', 'size': size, 'facing': f.serializedName},
        collisionShape: _boxes(whistleWall[size]!.get(f)),
        selectionShape: _boxes(whistleWall[size]!.get(f)),
      ),
  ],
];

/// `WhistleExtenderBlock.getShape`.
List<ShapeRule> whistleExtenderShapeRules() => [
  for (final shape in const ['single', 'double', 'double_connected'])
    for (final size in whistleSizes)
      ShapeRule(
        when: {'shape': shape, 'size': size},
        collisionShape: _boxes(whistleExtender(shape, size)),
        selectionShape: _boxes(whistleExtender(shape, size)),
      ),
];
