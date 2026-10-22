// Builds the `CreateBlock` of a manifest entry (exact properties, defaults and
// stats from the Java registration) so the redstone blocks cannot drift from the
// state ids a Create client computes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show mapColorIdOf;
import '../../core/blocks.dart';
import '../../manifest/manifest.dart';

final Map<String, ManifestBlock> _byKey = {for (final b in kBlocks) b.key: b};

/// The manifest entry of `create:[key]` (the key without namespace).
ManifestBlock manifestBlockOf(String key) =>
    _byKey[key] ?? (throw StateError('create:$key is not in the block manifest'));

/// The host property of a manifest property (value order = state numbering).
BlockProperty hostProperty(ManifestProperty p) => switch (p.type) {
  'bool' => BlockProperty.boolean(p.name),
  'int' => BlockProperty.intRange(p.name, int.parse(p.values.first), int.parse(p.values.last)),
  _ => BlockProperty.enumeration(p.name, p.values),
};

/// The vanilla sound type name of a manifest `SoundType` constant.
String soundTypeName(String manifest) => switch (manifest) {
  'custom' => 'stone',
  final s => s.toLowerCase(),
};

/// `CreateBlock` for the manifest block [key]. [luminance] overrides the manifest and [lightRules]
/// carry a Java `lightLevel(state -> ...)`, which the manifest only records as dynamic.
CreateBlock buildManifestBlock(
  String key, {
  BlockBehavior? behavior,
  String? blockEntityType,
  List<PlacementRule> placement = const [],
  BlockShape? collisionShape,
  BlockShape? selectionShape,
  List<ShapeRule> shapeRules = const [],
  List<String> tags = const [],
  int? luminance,
  List<LightRule> lightRules = const [],
  PistonBehavior? pistonBehavior,
  BlockDrops? drops,
  bool? hasItem,
}) {
  final m = manifestBlockOf(key);
  final shape = m.noCollision ? BlockShape.empty : BlockShape.fullCube;
  return CreateBlock(
    key: 'create:$key',
    properties: [for (final p in m.properties) hostProperty(p)],
    defaultState: Map<String, String>.of(m.defaultState),
    hardness: m.hardness,
    blastResistance: m.blastResistance,
    requiresCorrectTool: m.requiresCorrectTool,
    soundType: soundTypeName(m.soundType),
    luminance: luminance ?? (m.lightDynamic ? 0 : m.lightLevel),
    lightRules: lightRules,
    ignitedByLava: m.ignitedByLava,
    canOcclude: !m.noOcclusion,
    mapColor: mapColorIdOf(m.mapColor),
    replaceable: m.replaceable,
    collisionShape: collisionShape ?? shape,
    selectionShape: selectionShape ?? BlockShape.fullCube,
    shapeRules: shapeRules,
    // The mineable tags come from the content module's tag registration.
    tags: tags,
    drops: drops ?? BlockDrops.selfItem,
    pistonBehavior: pistonBehavior ?? _piston(m.pushReaction),
    placement: placement,
    hasItem: hasItem ?? m.blockItem != null,
    itemKey: m.blockItem == null ? null : 'create:${m.blockItem}',
    blockEntityType: blockEntityType,
    behavior: behavior,
  );
}

PistonBehavior _piston(String pushReaction) => switch (pushReaction) {
  'DESTROY' || 'POPPED' => PistonBehavior.destroy,
  'BLOCK' => PistonBehavior.block,
  'IGNORE' => PistonBehavior.ignore,
  'PUSH_ONLY' => PistonBehavior.pushOnly,
  _ => PistonBehavior.normal,
};
