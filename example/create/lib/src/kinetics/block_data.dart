// The definition data of the kinetic blocks, from the manifest (pure, so the
// tests can run the host's block validation on all of them).
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../manifest/manifest.dart';
import 'shapes.dart';

final Map<String, ManifestBlock> _manifestByKey = {for (final b in kBlocks) b.key: b};

/// The manifest entry of the block `create:<path>`.
ManifestBlock manifestBlockOf(String path) =>
    _manifestByKey[path] ?? (throw ArgumentError.value(path, 'path', 'Not in the block manifest'));

BlockProperty _property(ManifestProperty p) => switch (p.type) {
  'bool' => BlockProperty.boolean(p.name),
  'int' => BlockProperty.intRange(p.name, int.parse(p.values.first), int.parse(p.values.last)),
  _ => BlockProperty.enumeration(p.name, p.values),
};

PistonBehavior _piston(String manifest) => switch (manifest) {
  'DESTROY' => PistonBehavior.destroy,
  'BLOCK' => PistonBehavior.block,
  'IGNORE' => PistonBehavior.ignore,
  'PUSH_ONLY' => PistonBehavior.pushOnly,
  _ => PistonBehavior.normal,
};

/// What a `CreateBlock` of this module is made of.
final class KineticBlockData {
  final String key;
  final List<BlockProperty> properties;
  final Map<String, String> defaultState;
  final double hardness;
  final double blastResistance;
  final bool requiresCorrectTool;
  final String soundType;
  final int luminance;
  final bool canOcclude;
  final bool replaceable;
  final BlockShape collisionShape;
  final BlockShape selectionShape;
  final List<ShapeRule> shapeRules;
  final BlockDrops drops;
  final List<String> tags;
  final PistonBehavior pistonBehavior;
  final String? itemKey;
  final int? itemMaxStackSize;

  const KineticBlockData({
    required this.key,
    required this.properties,
    required this.defaultState,
    required this.hardness,
    required this.blastResistance,
    required this.requiresCorrectTool,
    required this.soundType,
    required this.luminance,
    required this.canOcclude,
    required this.replaceable,
    required this.collisionShape,
    required this.selectionShape,
    required this.shapeRules,
    required this.drops,
    required this.tags,
    required this.pistonBehavior,
    required this.itemKey,
    required this.itemMaxStackSize,
  });

  /// The host's block definition for this data.
  BlockDefinition toDefinition() => BlockDefinition(
    key: key,
    properties: properties,
    defaultState: defaultState,
    hardness: hardness,
    blastResistance: blastResistance,
    requiresCorrectTool: requiresCorrectTool,
    soundType: soundType,
    luminance: luminance,
    canOcclude: canOcclude,
    replaceable: replaceable,
    collisionShape: collisionShape,
    selectionShape: selectionShape,
    drops: drops,
    tags: tags,
    shapeRules: shapeRules,
    pistonBehavior: pistonBehavior,
  );
}

int? _itemMaxStack(String? itemKey) {
  if (itemKey == null) return null;
  for (final i in kItems) {
    if (i.key == itemKey) return i.maxStack == 64 ? null : i.maxStack;
  }
  return null;
}

/// The data of `create:<path>`: manifest stats and properties, the shapes of
/// [kineticShapeRules] unless overridden, Create's generated loot table.
KineticBlockData kineticBlockData(
  String path, {
  BlockShape? collisionShape,
  BlockShape? selectionShape,
  List<ShapeRule>? shapeRules,
  PistonBehavior? pistonBehavior,
  bool? canOcclude,
  bool useLootTable = true,
}) {
  final m = manifestBlockOf(path);
  final rules = shapeRules ?? kineticShapeRules[path] ?? const <ShapeRule>[];
  return KineticBlockData(
    key: 'create:${m.key}',
    properties: [for (final p in m.properties) _property(p)],
    defaultState: m.defaultState,
    hardness: m.hardness,
    blastResistance: m.blastResistance,
    requiresCorrectTool: m.requiresCorrectTool,
    soundType: m.soundType.toLowerCase(),
    luminance: m.lightDynamic ? 0 : m.lightLevel,
    canOcclude: canOcclude ?? !m.noOcclusion,
    replaceable: m.replaceable,
    collisionShape: collisionShape ?? kineticBaseShapes[path] ?? (m.noCollision ? BlockShape.empty : BlockShape.fullCube),
    selectionShape: selectionShape ?? kineticBaseShapes[path] ?? BlockShape.fullCube,
    shapeRules: rules,
    drops: useLootTable ? BlockDrops.lootTable('create:blocks/${m.key}') : BlockDrops.selfItem,
    tags: [for (final k in m.mineable) 'minecraft:mineable/$k'],
    pistonBehavior: pistonBehavior ?? kineticPistonBehavior[path] ?? _piston(m.pushReaction),
    itemKey: m.blockItem == null ? null : 'create:${m.blockItem}',
    itemMaxStackSize: _itemMaxStack(m.blockItem),
  );
}

/// The paths of all kinetic blocks of this module (the block data is complete for all of them).
List<String> get kineticBlockPaths => [
  'shaft',
  'cogwheel',
  'large_cogwheel',
  'andesite_encased_shaft',
  'brass_encased_shaft',
  'andesite_encased_cogwheel',
  'brass_encased_cogwheel',
  'andesite_encased_large_cogwheel',
  'brass_encased_large_cogwheel',
  'gearbox',
  'clutch',
  'gearshift',
  'encased_chain_drive',
  'adjustable_chain_gearshift',
  'creative_motor',
  'water_wheel',
  'large_water_wheel',
  'water_wheel_structure',
  'turntable',
  'hand_crank',
  'cuckoo_clock',
  'mysterious_cuckoo_clock',
  'speedometer',
  'stressometer',
  'copper_valve_handle',
  for (final c in dyeColorNames) '${c}_valve_handle',
  'steam_engine',
  'powered_shaft',
  'sequenced_gearshift',
  'flywheel',
  'rotation_speed_controller',
];

/// The sixteen dye colours.
const List<String> dyeColorNames = [
  'white',
  'orange',
  'magenta',
  'light_blue',
  'yellow',
  'lime',
  'pink',
  'gray',
  'light_gray',
  'cyan',
  'purple',
  'blue',
  'brown',
  'green',
  'red',
  'black',
];
