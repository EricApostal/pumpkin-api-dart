// Block shapes of the kinetic blocks (`AllShapes`), as shape rules per state.
// Pure apart from the `pumpkin_api_core` shape model.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'geometry.dart';

/// A box in the local frame of a "directional" shape: [u] and [v] run across
/// the block, [t] runs from the back (0) to the front (16), all in 16ths.
final class LocalBox {
  final double u0, t0, v0, u1, t1, v1;

  const LocalBox(this.u0, this.t0, this.v0, this.u1, this.t1, this.v1);
}

double _f(double v) => v / 16;

BlockBox _box(
  double x0,
  double y0,
  double z0,
  double x1,
  double y1,
  double z1,
) => BlockBox(_f(x0), _f(y0), _f(z0), _f(x1), _f(y1), _f(z1));

/// Places [b] in the world frame for a shape facing [facing] (`VoxelShaper.forDirectional`):
/// the back of the shape sits at the side opposite to [facing]. [longAxis] says where the local
/// `v` axis goes (defaults to a fixed choice; shapes symmetric across the facing do not care).
BlockBox orient(LocalBox b, Dir facing, {KAxis? uAxis, KAxis? vAxis}) {
  final a = facing.axis;
  final others = KAxis.values.where((x) => x != a).toList();
  final ua = uAxis ?? others[0];
  final va = vAxis ?? others[1];

  double t0 = b.t0;
  double t1 = b.t1;
  if (!facing.isPositive) {
    t0 = 16 - b.t1;
    t1 = 16 - b.t0;
  }

  final lo = <KAxis, double>{ua: b.u0, va: b.v0, a: t0};
  final hi = <KAxis, double>{ua: b.u1, va: b.v1, a: t1};
  return _box(
    lo[KAxis.x]!,
    lo[KAxis.y]!,
    lo[KAxis.z]!,
    hi[KAxis.x]!,
    hi[KAxis.y]!,
    hi[KAxis.z]!,
  );
}

/// A shape rule per value of the direction property [property] (`facing`).
List<ShapeRule> directionalRules(
  String property,
  List<LocalBox> boxes, {
  Iterable<Dir> directions = Dir.values,
  Map<String, String> extraWhen = const {},
}) => [
  for (final d in directions)
    ShapeRule(
      when: {property: d.name, ...extraWhen},
      collisionShape: BlockShape.boxes([for (final b in boxes) orient(b, d)]),
      selectionShape: BlockShape.boxes([for (final b in boxes) orient(b, d)]),
    ),
];

/// A box given for the Y axis, as seen on the other axes (`VoxelShaper.forAxis`).
BlockBox axisBox(
  double x0,
  double y0,
  double z0,
  double x1,
  double y1,
  double z1,
  KAxis axis,
) => switch (axis) {
  KAxis.y => _box(x0, y0, z0, x1, y1, z1),
  KAxis.x => _box(y0, x0, z0, y1, x1, z1),
  KAxis.z => _box(x0, z0, y0, x1, z1, y1),
};

/// A shape rule per axis from boxes given for the Y axis (x0,y0,z0,x1,y1,z1 in 16ths).
List<ShapeRule> axisRules(
  String property,
  List<List<double>> boxesForY, {
  Map<String, String> extraWhen = const {},
}) => [
  for (final axis in KAxis.values)
    ShapeRule(
      when: {property: axis.name, ...extraWhen},
      collisionShape: BlockShape.boxes([
        for (final b in boxesForY)
          axisBox(b[0], b[1], b[2], b[3], b[4], b[5], axis),
      ]),
      selectionShape: BlockShape.boxes([
        for (final b in boxesForY)
          axisBox(b[0], b[1], b[2], b[3], b[4], b[5], axis),
      ]),
    ),
];

/// `SIX_VOXEL_POLE` for Y.
const List<double> sixVoxelPole = [5, 0, 5, 11, 16, 11];

/// `EIGHT_VOXEL_POLE` for Y.
const List<double> eightVoxelPole = [4, 0, 4, 12, 16, 12];

/// `SMALL_GEAR_SHAPE` + pole.
const List<List<double>> smallGear = [
  [2, 6, 2, 14, 10, 14],
  sixVoxelPole,
];

/// `LARGE_GEAR_SHAPE` + pole.
const List<List<double>> largeGear = [
  [0, 6, 0, 16, 10, 16],
  sixVoxelPole,
];

/// `MOTOR_BLOCK` (facing = the shaft side).
const List<LocalBox> motorBlock = [LocalBox(3, 0, 3, 13, 14, 13)];

/// `CRANK` (back at the wall).
const List<LocalBox> crank = [
  LocalBox(5, 0, 5, 11, 6, 11),
  LocalBox(1, 3, 1, 15, 8, 15),
];

/// `VALVE_HANDLE`.
const List<LocalBox> valveHandle = [
  LocalBox(5, 0, 5, 11, 4, 11),
  LocalBox(1, 3, 1, 15, 8, 15),
];

/// `TURNTABLE_SHAPE`.
final BlockShape turntableShape = BlockShape.boxes([
  _box(1, 4, 1, 15, 8, 15),
  _box(5, 0, 5, 11, 4, 11),
]);

/// `SPEED_CONTROLLER`.
final BlockShape speedControllerShape = BlockShape.boxes([
  _box(0, 0, 0, 16, 4, 16),
  _box(1, 1, 1, 15, 13, 15),
  _box(0, 8, 0, 16, 14, 16),
]);

/// `CUCKOO_CLOCK`.
final BlockShape cuckooClockShape = BlockShape.boxes([
  _box(1, 0, 1, 15, 19, 15),
]);

/// `GAUGE_SHAPE_UP` oriented by the gauge's facing and `axis_along_first`
/// (`GaugeShaper`).
List<ShapeRule> gaugeRules() {
  const base = [
    LocalBox(1, 0, 0, 15, 2, 16),
    LocalBox(2, 2, 1, 14, 14, 15),
  ]; // u = x, t = y, v = z (long)
  KAxis longAxis(Dir facing, bool alongFirst) => switch (facing.axis) {
    KAxis.y => alongFirst ? KAxis.x : KAxis.z,
    KAxis.z => alongFirst ? KAxis.x : KAxis.y,
    KAxis.x => alongFirst ? KAxis.z : KAxis.y,
  };
  final rules = <ShapeRule>[];
  for (final d in Dir.values) {
    for (final alongFirst in [true, false]) {
      final la = longAxis(d, alongFirst);
      final others = KAxis.values.where((x) => x != d.axis && x != la).toList();
      final boxes = [
        for (final b in base) orient(b, d, uAxis: others.single, vAxis: la),
      ];
      rules.add(
        ShapeRule(
          when: {'facing': d.name, 'axis_along_first': '$alongFirst'},
          collisionShape: BlockShape.boxes(boxes),
          selectionShape: BlockShape.boxes(boxes),
        ),
      );
    }
  }
  return rules;
}

/// The per-state shape rules of the kinetic blocks, by block path.
final Map<String, List<ShapeRule>> kineticShapeRules = {
  'shaft': axisRules('axis', [sixVoxelPole]),
  'cogwheel': axisRules('axis', smallGear),
  'large_cogwheel': axisRules('axis', largeGear),
  'flywheel': axisRules('axis', largeGear),
  'powered_shaft': axisRules('axis', [eightVoxelPole]),
  'gantry_shaft': directionalRules('facing', const [
    LocalBox(4, 0, 4, 12, 16, 12),
  ]),
  'creative_motor': directionalRules('facing', motorBlock),
  'hand_crank': directionalRules('facing', crank),
  'copper_valve_handle': directionalRules('facing', valveHandle),
  for (final c in _dyeColors)
    '${c}_valve_handle': directionalRules('facing', valveHandle),
  'speedometer': gaugeRules(),
  'stressometer': gaugeRules(),
};

/// Shapes of blocks that have one shape for every state.
final Map<String, BlockShape> kineticBaseShapes = {
  'turntable': turntableShape,
  'cuckoo_clock': cuckooClockShape,
  'mysterious_cuckoo_clock': cuckooClockShape,
  'rotation_speed_controller': speedControllerShape,
};

/// Piston behaviour where Create overrides `getPistonPushReaction`.
const Map<String, PistonBehavior> kineticPistonBehavior = {
  'shaft': PistonBehavior.normal,
  'cogwheel': PistonBehavior.normal,
  'large_cogwheel': PistonBehavior.normal,
  'andesite_encased_shaft': PistonBehavior.normal,
  'brass_encased_shaft': PistonBehavior.normal,
  'encased_chain_drive': PistonBehavior.normal,
  'adjustable_chain_gearshift': PistonBehavior.normal,
  'clutch': PistonBehavior.normal,
  'gearshift': PistonBehavior.normal,
  'powered_shaft': PistonBehavior.normal,
  'gearbox': PistonBehavior.pushOnly,
  'water_wheel_structure': PistonBehavior.block,
};

const List<String> _dyeColors = [
  'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
  'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black', //
];
