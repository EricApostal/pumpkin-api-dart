// Block descriptions: key, properties, shapes and callbacks in one declarative
// object that the plugin turns into a host `BlockDefinition`, a registered
// `BlockBehavior`, placement rules and the block entity glue.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'block_entity.dart';

/// Block state properties with vanilla's value order (which numbers the states).
abstract final class CreateProps {
  static final BlockProperty axis = BlockProperty.enumeration('axis', ['x', 'y', 'z']);

  /// `BlockStateProperties.FACING`: all six directions, in Java's value order.
  ///
  /// Java is `DirectionProperty.of("facing", NORTH, EAST, SOUTH, WEST, UP, DOWN)` —
  /// read straight out of the client jar the user runs
  /// (`BlockStateProperties.FACING.getPossibleValues()` -> `[north, east, south, west,
  /// up, down]`), and the same list is in the port's own extractor
  /// (`tool/REPORT_blocks.md`) and its generated manifest (`manifest/blocks.g.dart`).
  /// This list used to be `Direction.values()` order (`down, up, north, south, west,
  /// east`), which the host numbered as declared and the client then read with Java's
  /// order: index *i* meant a different direction on both sides, so every block with
  /// this 6-valued property was placed rotated (north -> south, up -> east) even
  /// though the placement rules chose the right direction.
  static final BlockProperty facing = BlockProperty.enumeration('facing', ['north', 'east', 'south', 'west', 'up', 'down']);

  /// `HORIZONTAL_FACING` (also named `facing`).
  static final BlockProperty horizontalFacing = BlockProperty.enumeration('facing', ['north', 'south', 'west', 'east']);

  static final BlockProperty waterlogged = BlockProperty.boolean('waterlogged');
  static final BlockProperty powered = BlockProperty.boolean('powered');
  static final BlockProperty open = BlockProperty.boolean('open');
  static final BlockProperty lit = BlockProperty.boolean('lit');

  /// An integer property from 0 to [max] (`BlockStateProperties.LEVEL`-like).
  static BlockProperty level(String name, int max, {int min = 0}) => BlockProperty.intRange(name, min, max);

  /// A boolean property.
  static BlockProperty flag(String name) => BlockProperty.boolean(name);
}

/// One block of the mod.
class CreateBlock {
  /// `create:<path>`.
  final String key;
  final List<BlockProperty> properties;

  /// Values that differ from "first value of each property". Boolean properties
  /// that are not listed default to `false` when [booleansDefaultFalse] is set
  /// (vanilla's usual `registerDefaultState(... false)`), because the host's
  /// first boolean value is `true`.
  final Map<String, String> defaultState;
  final bool booleansDefaultFalse;
  final double hardness;
  final double blastResistance;
  final bool requiresCorrectTool;
  final String soundType;

  /// Light level every state emits unless [lightRules] matches.
  final int luminance;

  /// Light levels per state (the host's `light-rules`), the first matching rule
  /// wins. Vanilla `lightLevel(state -> ...)`: a rose quartz lamp only lights up
  /// while `powering` is true.
  final List<LightRule> lightRules;

  final bool canOcclude;
  final bool replaceable;

  /// Vanilla `ignitedByLava()`: lava sets fire to the block. Whether *fire*
  /// spreads onto it is a separate question ([BlockBehavior.onFireSpread]).
  final bool ignitedByLava;
  final int mapColor;
  final BlockShape collisionShape;
  final BlockShape selectionShape;
  final List<ShapeRule> shapeRules;
  final List<ConnectRule> connectRules;
  final BlockDrops drops;
  final List<String> tags;
  final PistonBehavior pistonBehavior;

  /// How placing the block chooses properties.
  final List<PlacementRule> placement;

  /// The key of the block item registered with the block (`null`: none). Defaults
  /// to the block key.
  final String? itemKey;
  final int? itemMaxStackSize;

  /// Key of the block entity type created when the block is placed.
  final String? blockEntityType;

  /// Extra hooks. The framework wraps `onPlaced` when [blockEntityType] is set.
  final BlockBehavior? behavior;

  CreateBlock({
    required this.key,
    this.properties = const [],
    this.defaultState = const {},
    this.booleansDefaultFalse = true,
    this.hardness = 1,
    this.blastResistance = 1,
    this.requiresCorrectTool = false,
    this.soundType = 'stone',
    this.luminance = 0,
    this.lightRules = const [],
    this.canOcclude = true,
    this.replaceable = false,
    this.ignitedByLava = false,
    this.mapColor = 0,
    this.collisionShape = BlockShape.fullCube,
    this.selectionShape = BlockShape.fullCube,
    this.shapeRules = const [],
    this.connectRules = const [],
    this.drops = BlockDrops.selfItem,
    this.tags = const [],
    this.pistonBehavior = PistonBehavior.normal,
    this.placement = const [],
    bool hasItem = true,
    String? itemKey,
    this.itemMaxStackSize,
    this.blockEntityType,
    this.behavior,
  }) : itemKey = hasItem ? (itemKey ?? key) : null;

  /// The id of the block's first state; set when the registry is applied.
  int baseStateId = -1;

  /// The host block id; set when the registry is applied.
  int blockId = -1;

  late final BlockDefinition definition = BlockDefinition(
    key: key,
    properties: properties,
    defaultState: {
      if (booleansDefaultFalse)
        for (final p in properties)
          if (p.isBoolean) p.name: 'false',
      ...defaultState,
    },
    hardness: hardness,
    blastResistance: blastResistance,
    requiresCorrectTool: requiresCorrectTool,
    soundType: soundType,
    luminance: luminance,
    lightRules: lightRules,
    canOcclude: canOcclude,
    replaceable: replaceable,
    ignitedByLava: ignitedByLava,
    mapColor: mapColor,
    collisionShape: collisionShape,
    selectionShape: selectionShape,
    connectRules: connectRules,
    drops: drops,
    tags: tags,
    shapeRules: shapeRules,
    pistonBehavior: pistonBehavior,
  );

  late final BlockStateLayout layout = definition.layout;

  /// The property values of the state with [stateIndex] (as in the events).
  Map<String, String> stateOf(int stateIndex) => layout.valuesAt(stateIndex);

  /// The global state id for property [values] (missing ones take the default).
  int stateId(Map<String, String> values) => baseStateId + layout.indexOf({...definition.defaultState, ...values});

  /// The behaviour to register with the host, or `null` when the block has no hooks.
  BlockBehavior? buildBehavior(BlockEntityStore store) {
    final type = blockEntityType;
    final user = behavior;
    if (type == null) return user;
    FutureOr<void> placed(Server server, CustomBlockPlacedEventData e) {
      store.createAt(
        e.targetWorld,
        e.pos,
        type,
        placedBy: e.player?.asString,
      );
      return user?.onPlaced?.call(server, e);
    }

    if (user == null) return BlockBehavior(onPlaced: placed);
    return BlockBehavior(
      onNeighborUpdate: user.onNeighborUpdate,
      onPlaced: placed,
      onStateReplaced: user.onStateReplaced,
      onBroken: user.onBroken,
      onScheduledTick: user.onScheduledTick,
      onRandomTick: user.onRandomTick,
      onEntityCollision: user.onEntityCollision,
      onEntityStep: user.onEntityStep,
      onCanPlace: user.onCanPlace,
      onUpdateShape: user.onUpdateShape,
      onWeakPower: user.onWeakPower,
      onStrongPower: user.onStrongPower,
      onComparatorOutput: user.onComparatorOutput,
      onShape: user.onShape,
      onEntityCollisionShape: user.onEntityCollisionShape,
      onUse: user.onUse,
      onUseWithItem: user.onUseWithItem,
      onUseWithoutItem: user.onUseWithoutItem,
      onAttack: user.onAttack,
      onCloneItem: user.onCloneItem,
      onPlayerWillDestroy: user.onPlayerWillDestroy,
      onFriction: user.onFriction,
      onSpeedFactor: user.onSpeedFactor,
      onJumpFactor: user.onJumpFactor,
      canEntityDestroy: user.canEntityDestroy,
      isPathfindable: user.isPathfindable,
      canConnectRedstone: user.canConnectRedstone,
      onLandedUpon: user.onLandedUpon,
      soundType: user.soundType,
      onFireSpread: user.onFireSpread,
      redstoneOutput: user.redstoneOutput,
      comparatorOutput: user.comparatorOutput,
      priority: user.priority,
    );
  }
}
