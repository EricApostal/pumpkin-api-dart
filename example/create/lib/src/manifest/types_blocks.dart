// Plain const data classes for the generated block / item manifest
// (blocks.g.dart, items.g.dart). Hand written; no dependencies.

/// One block state property as registered by Create / Minecraft.
///
/// `values` is the exact declared value order, which determines block state ids:
/// properties are sorted by [name] (ascending), the first property is the slowest
/// varying and the last one the fastest varying when state ids are assigned.
class ManifestProperty {
  const ManifestProperty(this.name, this.type, this.values, {this.verified = true});

  final String name;

  /// 'bool' (values `true`,`false`), 'int' (`min..max`) or 'enum' (serialized names).
  final String type;
  final List<String> values;

  /// False when the values could not be fully evaluated from the sources.
  final bool verified;

  @override
  String toString() => '$name=${values.join('|')}';
}

class ManifestBlock {
  const ManifestBlock({
    required this.key,
    required this.index,
    required this.javaClass,
    required this.source,
    this.properties = const [],
    this.defaultState = const {},
    this.stateCount = 1,
    this.stateOffset = 0,
    this.waterlogged = false,
    this.hardness = 0,
    this.blastResistance = 0,
    this.requiresCorrectTool = false,
    this.lightLevel = 0,
    this.lightDynamic = false,
    this.soundType = 'STONE',
    this.mapColor = 'NONE',
    this.noOcclusion = false,
    this.noCollision = false,
    this.isAir = false,
    this.redstoneConductor,
    this.suffocating,
    this.viewBlocking,
    this.forceSolid,
    this.pushReaction = 'NORMAL',
    this.friction = 0.6,
    this.speedFactor = 1.0,
    this.jumpFactor = 1.0,
    this.noLootTable = false,
    this.ignitedByLava = false,
    this.randomTicks = false,
    this.replaceable = false,
    this.dynamicShape = false,
    this.blockItem,
    this.mineable = const [],
    this.stressImpact,
    this.stressCapacity,
    this.verified = true,
    this.notes = const [],
  });

  /// Registry path in the `create` namespace.
  final String key;

  /// Registration order (0-based) among Create's blocks.
  final int index;

  /// Fully qualified Java class of the Block (the class the factory instantiates).
  final String javaClass;

  /// Where the registration lives (e.g. `AllBlocks.SHAFT`, `AllBlocks.SEATS[red]`).
  final String source;

  /// Properties sorted by name (state id order, see [ManifestProperty]).
  final List<ManifestProperty> properties;

  /// Default state: property name -> value.
  final Map<String, String> defaultState;

  /// Number of block states (product of the property value counts).
  final int stateCount;

  /// Sum of [stateCount] of all earlier Create blocks (state id offset relative to
  /// the first Create state; add the number of states registered before Create).
  final int stateOffset;
  final bool waterlogged;

  // --- BlockBehaviour.Properties -------------------------------------------
  final double hardness;
  final double blastResistance;
  final bool requiresCorrectTool;

  /// Constant light emission; when [lightDynamic] it is the maximum constant found
  /// in the state-dependent expression (0 when unknown).
  final int lightLevel;
  final bool lightDynamic;

  /// `SoundType` constant name (`STONE`, `WOOD`, ..., or `custom`).
  final String soundType;

  /// `MapColor` constant name, `dye:<DYE>` (colour of the dye), `from:<expr>` or `dynamic`.
  final String mapColor;
  final bool noOcclusion;
  final bool noCollision;
  final bool isAir;

  /// null = vanilla default behaviour (derived from the shape).
  final bool? redstoneConductor;
  final bool? suffocating;
  final bool? viewBlocking;

  /// 'on' (forceSolidOn), 'off' (forceSolidOff) or null.
  final String? forceSolid;
  final String pushReaction;
  final double friction;
  final double speedFactor;
  final double jumpFactor;
  final bool noLootTable;
  final bool ignitedByLava;
  final bool randomTicks;
  final bool replaceable;
  final bool dynamicShape;

  /// Key of the block item (same as [key]) or null if the block has no item.
  final String? blockItem;

  /// `mineable_with_*` tool kinds from the registration (`pickaxe`, `axe`).
  final List<String> mineable;

  /// Default stress impact / capacity registered through `CStress` (su), if any.
  final double? stressImpact;
  final double? stressCapacity;

  /// False if something about this entry could not be extracted reliably.
  final bool verified;
  final List<String> notes;

  @override
  String toString() => 'ManifestBlock($key)';
}

class ManifestItem {
  const ManifestItem({
    required this.key,
    required this.index,
    required this.javaClass,
    required this.source,
    this.maxStack = 64,
    this.isBlockItem = false,
    this.blockKey,
    this.durability,
    this.fireResistant = false,
    this.rarity = 'COMMON',
    this.food = false,
    this.burnTime,
    this.components = const [],
    this.verified = true,
    this.notes = const [],
  });

  final String key;

  /// Registration order (0-based) among Create's items (block items included).
  final int index;
  final String javaClass;
  final String source;
  final int maxStack;
  final bool isBlockItem;
  final String? blockKey;

  /// Max damage when the item is damageable (implies maxStack 1); -1 if unknown.
  final int? durability;
  final bool fireResistant;

  /// `Rarity` constant name.
  final String rarity;

  /// True when the item has a food component (see [components] for the builder text).
  final bool food;

  /// Fuel burn time in ticks if registered through Registrate's `burnTime`.
  final int? burnTime;

  /// Textual descriptions of other Item.Properties components (not evaluated).
  final List<String> components;
  final bool verified;
  final List<String> notes;

  @override
  String toString() => 'ManifestItem($key)';
}
