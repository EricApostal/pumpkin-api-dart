// The 16 blocks CC: Tweaked registers, as host block definitions: registry
// key, block state properties, default state, strength, shapes, drops, tags
// and the item that places each. Binding-free (it only needs
// `pumpkin_api_core`), so it can be checked without a server.
//
// Source: CC: Tweaked, branch `mc-26.3`, commit 8b64fc4c (the one
// docs/client-compat.md was read at), under
// `projects/common/src/main/java/dan200/computercraft/`:
//
//   shared/ModRegistry.java                          Blocks (strength, map colour), Items (the block items)
//   shared/computer/blocks/ComputerBlock.java        FACING, STATE
//   shared/computer/blocks/CommandComputerBlock.java GameMasterBlock
//   shared/computer/blocks/AbstractComputerBlock.java
//   shared/computer/core/ComputerState.java          off, on, blinking
//   shared/turtle/blocks/TurtleBlock.java            FACING, WATERLOGGED, shape 2/16..14/16
//   shared/peripheral/speaker/SpeakerBlock.java      FACING
//   shared/peripheral/diskdrive/DiskDriveBlock.java  FACING, STATE (empty, full, invalid)
//   shared/peripheral/printer/PrinterBlock.java      FACING, TOP, BOTTOM
//   shared/peripheral/monitor/MonitorBlock.java      ORIENTATION, FACING, STATE
//   shared/peripheral/monitor/MonitorEdgeState.java  the 16 edge states
//   shared/peripheral/modem/wireless/WirelessModemBlock.java  FACING (six), ON, WATERLOGGED
//   shared/peripheral/modem/ModemShapes.java         the six modem plates
//   shared/peripheral/modem/wired/WiredModemFullBlock.java    MODEM, PERIPHERAL
//   shared/peripheral/modem/wired/CableBlock.java    MODEM, CABLE, six sides, WATERLOGGED
//   shared/peripheral/modem/wired/CableModemVariant.java      the 25 modem variants
//   shared/peripheral/modem/wired/CableShapes.java   core and arms
//   shared/peripheral/modem/wired/CableBlockItem.java         the cable and wired_modem items
//   shared/lectern/CustomLecternBlock.java           extends vanilla LecternBlock
//   shared/peripheral/redstone/RedstoneRelayBlock.java        FACING
//
// and the generated tags in `projects/common/src/generated/resources/data/`
// (`computercraft/tags/block/{computer,monitor,turtle,wired_modem}.json`,
// `minecraft/tags/block/{mineable/pickaxe,mineable/axe,wither_immune}.json`).
//
// State numbering: the properties sorted by name, the first one the most
// significant, values in the order a property lists them, booleans `true`
// first (docs/block-registry.md, vanilla's `StateDefinition`). The client
// numbers the states of CC's blocks that way after all vanilla states, in the
// order of `CcRegistries.blocks`, so the host must produce the same ids.
//
// THE STATE COUNT IS 6940, NOT 3740. docs/client-compat.md first said 3740
// because it counted the cable as 3200 states. The cable has 25 modem
// variants x 2 (`cable`) x 2^6 (the six sides) x 2 (`waterlogged`) = 6400. The
// other fifteen blocks add 540. The host limits a block to 4096 states
// (`BlockRegistryChecks.maxStatesPerBlock`), so the cable cannot be registered
// completely yet; see [CcBlockSpec.hostFixed] and [CcBlockCatalog.plan].
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// One CC block as the host will know it.
final class CcBlockSpec {
  /// The path of the id (`computercraft:<name>`).
  final String name;

  /// The Java class that defines the properties and behaviour.
  final String javaClass;

  /// The path of the item that places the block (`set-block-item`), or `null`
  /// when no item of the mod does (the lectern is placed by replacing the
  /// vanilla lectern).
  final String? item;

  /// Every state property of the block, as Java's `createBlockStateDefinition`
  /// declares them (their order here is irrelevant for the numbering).
  final List<BlockProperty> properties;

  /// The default state (`registerDefaultState`). Properties that are not
  /// listed start at their first value, so every boolean that starts `false`
  /// and every enum whose default is not its first value is listed.
  final Map<String, String> defaultState;

  /// The number of states Java's `StateDefinition` has (the product of the
  /// value counts), written down independently of [properties] so that a
  /// mistake in either is caught.
  final int expectedStates;

  /// `strength(hardness, resistance)`.
  final double hardness;
  final double blastResistance;

  /// `MapColor` id (`STONE` 11, `GOLD` 30, `WOOD` 13).
  final int mapColor;

  /// Whether the block is a full cube. Selects `canOcclude` and `suffocating`
  /// of the definition: a block with a smaller shape does not occlude light
  /// and does not suffocate.
  final bool fullCube;

  /// The shape used for collision and selection (the host has one shape for
  /// all states).
  final BlockShape shape;

  /// How placing the block chooses its properties: what the Java block's
  /// `getStateForPlacement` does with `facing`, `orientation` and `waterlogged`
  /// (`block-placement.wit`). Empty: the default state.
  final List<PlacementRule> placement;

  final List<ConnectRule> connectRules;
  final BlockDrops drops;
  final String soundType;

  /// Properties the host definition leaves out, with the value they keep,
  /// *only if* the block would otherwise exceed the host's state limit. They
  /// must be the most significant properties (first in name order) and their
  /// kept value must be the first one of the property, so that the states that
  /// remain have the same ids as the client's: dropping `cable` (the first
  /// name of the cable block, kept `true`) leaves exactly the client's states
  /// 0 to 3199.
  final Map<String, String> hostFixed;

  /// What differs from the Java block, for the report and the README.
  final String note;

  CcBlockSpec({
    required this.name,
    required this.javaClass,
    required this.item,
    required this.properties,
    required this.defaultState,
    required this.expectedStates,
    required this.hardness,
    required this.blastResistance,
    required this.mapColor,
    required this.fullCube,
    required this.shape,
    this.placement = const [],
    this.connectRules = const [],
    this.drops = BlockDrops.selfItem,
    this.soundType = 'stone',
    this.hostFixed = const {},
    this.note = '',
  });

  /// `computercraft:<name>`.
  String get key => 'computercraft:$name';

  /// `computercraft:<item>`, or `null`.
  String? get itemKey => item == null ? null : 'computercraft:$item';

  /// The definition with all of Java's properties, minus [without] (names of
  /// properties to leave out; their connect rules go too).
  BlockDefinition definition({Set<String> without = const {}}) => BlockDefinition(
    key: key,
    properties: [
      for (final p in properties)
        if (!without.contains(p.name)) p,
    ],
    defaultState: {
      for (final e in defaultState.entries)
        if (!without.contains(e.key)) e.key: e.value,
    },
    hardness: hardness,
    blastResistance: blastResistance,
    requiresCorrectTool: false,
    soundType: soundType,
    luminance: 0,
    canOcclude: fullCube,
    suffocating: fullCube,
    mapColor: mapColor,
    collisionShape: shape,
    selectionShape: shape,
    connectRules: [
      for (final r in connectRules)
        if (!without.contains(r.property)) r,
    ],
    drops: drops,
  );

  /// The number of states Java's definition has, computed from [properties].
  int get javaStateCount => definition().stateCount;
}

/// What the plugin registers for one block: the (possibly reduced) host
/// definition, and how it relates to the client's block.
final class CcBlockPlan {
  final CcBlockSpec spec;

  /// What is registered with the host.
  final BlockDefinition definition;

  /// The properties of [spec] that [definition] leaves out.
  final Set<String> omitted;

  const CcBlockPlan(this.spec, this.definition, this.omitted);

  /// The states the client has for this block.
  int get clientStates => spec.javaStateCount;

  /// The states the host has.
  int get hostStates => definition.stateCount;

  /// Whether the host has every state the client has.
  bool get complete => omitted.isEmpty;

  /// The index, in the client's numbering of this block, of the state with
  /// index [hostIndex] of the host's numbering. Equal for every state when the
  /// omitted properties are the most significant ones kept at their first
  /// value (checked by [CcBlockCatalog.plan]).
  int clientIndexOf(int hostIndex) {
    final values = {...definition.layout.valuesAt(hostIndex), ...spec.hostFixed};
    return spec.definition().layout.indexOf(values);
  }
}

abstract final class CcBlockCatalog {
  static final BlockProperty _facing = BlockProperty.enumeration('facing', const [
    'north',
    'east',
    'south',
    'west',
  ]);

  /// `BlockStateProperties.FACING` (`DirectionalBlock`): the order of
  /// `Direction.values()`.
  static final BlockProperty _facingAll = BlockProperty.enumeration('facing', const [
    'down',
    'up',
    'north',
    'south',
    'west',
    'east',
  ]);

  static BlockProperty get _waterlogged => const BlockProperty.boolean('waterlogged');

  /// `ComputerState`.
  static final BlockProperty _computerState = BlockProperty.enumeration('state', const [
    'off',
    'on',
    'blinking',
  ]);

  /// `MonitorEdgeState`, in enum order.
  static const List<String> monitorEdgeStates = [
    'none', 'l', 'r', 'lr', 'u', 'd', 'ud', 'rd', //
    'ld', 'ru', 'lu', 'lrd', 'rud', 'lud', 'lru', 'lrud',
  ];

  /// `CableModemVariant`, in enum order: `none`, then for each of off, on,
  /// off_peripheral, on_peripheral the six sides in `Direction.values()` order.
  static final List<String> cableModemVariants = [
    'none',
    for (final suffix in ['off', 'on', 'off_peripheral', 'on_peripheral'])
      for (final direction in ['down', 'up', 'north', 'south', 'west', 'east']) '${direction}_$suffix',
  ];

  // Strength: `properties()` is `strength(2)`, `modemProperties()`
  // `strength(1.5f)`, `turtleProperties()` `strength(2.5f)`. `strength(x)` is
  // hardness x and blast resistance x. Nothing sets a sound or
  // `requiresCorrectToolForDrops`, so the sound is stone and any tool drops.
  static const int _stone = 11, _gold = 30; // MapColor ids

  static final BlockShape _plus = BlockShape.boxes(const [
    // CableShapes: the core and an arm for every side...
    BlockBox(0.375, 0.375, 0.375, 0.625, 0.625, 0.625),
    BlockBox(0.375, 0, 0.375, 0.625, 0.375, 0.625),
    BlockBox(0.375, 0.625, 0.375, 0.625, 1, 0.625),
    BlockBox(0.375, 0.375, 0, 0.625, 0.625, 0.375),
    BlockBox(0.375, 0.375, 0.625, 0.625, 0.625, 1),
    BlockBox(0, 0.375, 0.375, 0.375, 0.625, 0.625),
    BlockBox(0.625, 0.375, 0.375, 1, 0.625, 0.625),
    // ... and the six modem plates (ModemShapes).
    ..._modemPlates,
  ]);

  /// `ModemShapes.BOXES`: down, up, north, south, west, east.
  static const List<BlockBox> _modemPlates = [
    BlockBox(0.125, 0, 0.125, 0.875, 0.1875, 0.875),
    BlockBox(0.125, 0.8125, 0.125, 0.875, 1, 0.875),
    BlockBox(0.125, 0.125, 0, 0.875, 0.875, 0.1875),
    BlockBox(0.125, 0.125, 0.8125, 0.875, 0.875, 1),
    BlockBox(0, 0.125, 0.125, 0.1875, 0.875, 0.875),
    BlockBox(0.8125, 0.125, 0.125, 1, 0.875, 0.875),
  ];

  static CcBlockSpec _computer(String name, {required int mapColor, double hardness = 2, double resistance = 2, required String javaClass}) =>
      CcBlockSpec(
        name: name,
        javaClass: javaClass,
        item: name,
        properties: [_facing, _computerState],
        // ComputerBlock.getStateForPlacement: `getHorizontalDirection().getOpposite()`.
        placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
        defaultState: const {'facing': 'north', 'state': 'off'},
        expectedStates: 12,
        hardness: hardness,
        blastResistance: resistance,
        mapColor: mapColor,
        fullCube: true,
        shape: BlockShape.fullCube,
        note: 'The state `blinking`/`on` is driven by the block entity (not available).',
      );

  /// All 16 blocks, in registration order (the order of `CcRegistries.blocks`).
  static final List<CcBlockSpec> all = [
    _computer(
      'computer_normal',
      mapColor: _stone,
      javaClass: 'ComputerBlock (shared/computer/blocks), strength(2), MapColor.STONE',
    ),
    _computer(
      'computer_advanced',
      mapColor: _gold,
      javaClass: 'ComputerBlock, strength(2), MapColor.GOLD',
    ),
    _computer(
      'computer_command',
      mapColor: _stone,
      hardness: -1,
      resistance: 6000000,
      javaClass: 'CommandComputerBlock (GameMasterBlock), strength(-1, 6000000)',
    ),
    CcBlockSpec(
      name: 'turtle_normal',
      javaClass: 'TurtleBlock, strength(2.5), MapColor.STONE',
      item: 'turtle_normal',
      properties: [_facing, _waterlogged],
      // TurtleBlock.getStateForPlacement: `getHorizontalDirection()` and the fluid.
      placement: const [PlacementRule.horizontalFacing('facing'), PlacementRule.inWater('waterlogged')],
      defaultState: const {'facing': 'north', 'waterlogged': 'false'},
      expectedStates: 8,
      hardness: 2.5,
      blastResistance: 2.5,
      mapColor: 11,
      fullCube: false,
      // TurtleBlock.DEFAULT_SHAPE: 2/16 to 14/16 on every axis (Java moves it
      // by the block entity's animation offset, not modelled).
      shape: BlockShape.boxes(const [BlockBox(0.125, 0.125, 0.125, 0.875, 0.875, 0.875)]),
      note: 'Invisible block (RenderShape.INVISIBLE): the model comes from the block entity renderer.',
    ),
    CcBlockSpec(
      name: 'turtle_advanced',
      javaClass: 'TurtleBlock, strength(2.5), explosionResistance(2000), MapColor.GOLD',
      item: 'turtle_advanced',
      properties: [_facing, _waterlogged],
      // TurtleBlock.getStateForPlacement: `getHorizontalDirection()` and the fluid.
      placement: const [PlacementRule.horizontalFacing('facing'), PlacementRule.inWater('waterlogged')],
      defaultState: const {'facing': 'north', 'waterlogged': 'false'},
      expectedStates: 8,
      hardness: 2.5,
      blastResistance: 2000,
      mapColor: 30,
      fullCube: false,
      shape: BlockShape.boxes(const [BlockBox(0.125, 0.125, 0.125, 0.875, 0.875, 0.875)]),
      note: 'Invisible block (RenderShape.INVISIBLE): the model comes from the block entity renderer.',
    ),
    CcBlockSpec(
      name: 'speaker',
      javaClass: 'SpeakerBlock (HorizontalDirectionalBlock), strength(2), MapColor.STONE',
      item: 'speaker',
      properties: [_facing],
      // SpeakerBlock.getStateForPlacement: `getHorizontalDirection().getOpposite()`.
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      defaultState: const {'facing': 'north'},
      expectedStates: 4,
      hardness: 2,
      blastResistance: 2,
      mapColor: 11,
      fullCube: true,
      shape: BlockShape.fullCube,
    ),
    CcBlockSpec(
      name: 'disk_drive',
      javaClass: 'DiskDriveBlock (HorizontalContainerBlock), strength(2), MapColor.STONE',
      item: 'disk_drive',
      properties: [_facing, BlockProperty.enumeration('state', const ['empty', 'full', 'invalid'])],
      // HorizontalContainerBlock.getStateForPlacement: `getHorizontalDirection().getOpposite()`.
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      defaultState: const {'facing': 'north', 'state': 'empty'},
      expectedStates: 12,
      hardness: 2,
      blastResistance: 2,
      mapColor: 11,
      fullCube: true,
      shape: BlockShape.fullCube,
    ),
    CcBlockSpec(
      name: 'printer',
      javaClass: 'PrinterBlock (HorizontalContainerBlock), strength(2), MapColor.STONE',
      item: 'printer',
      properties: [_facing, const BlockProperty.boolean('top'), const BlockProperty.boolean('bottom')],
      // HorizontalContainerBlock.getStateForPlacement: `getHorizontalDirection().getOpposite()`.
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      defaultState: const {'facing': 'north', 'top': 'false', 'bottom': 'false'},
      expectedStates: 16,
      hardness: 2,
      blastResistance: 2,
      mapColor: 11,
      fullCube: true,
      shape: BlockShape.fullCube,
    ),
    for (final advanced in [false, true])
      CcBlockSpec(
        name: advanced ? 'monitor_advanced' : 'monitor_normal',
        javaClass: 'MonitorBlock (HorizontalDirectionalBlock), strength(2), MapColor.${advanced ? 'GOLD' : 'STONE'}',
        item: advanced ? 'monitor_advanced' : 'monitor_normal',
        properties: [
          // EnumProperty.create("orientation", Direction.class, UP, DOWN, NORTH):
          // the values in the order they are passed.
          BlockProperty.enumeration('orientation', const ['up', 'down', 'north']),
          _facing,
          BlockProperty.enumeration('state', monitorEdgeStates),
        ],
        defaultState: const {'orientation': 'north', 'facing': 'north', 'state': 'none'},
        // MonitorBlock.getStateForPlacement: `facing` is the opposite of the horizontal
        // direction; `orientation` is UP when the player looks down (pitch > 66.5), DOWN
        // when they look up (pitch < -66.5), NORTH otherwise (the property has no
        // `horizontal` value, so the default `north` stays).
        placement: const [
          PlacementRule.horizontalFacing('facing', opposite: true),
          PlacementRule.verticalLook('orientation', 66.5, opposite: true),
        ],
        expectedStates: 192,
        hardness: 2,
        blastResistance: 2,
        mapColor: advanced ? 30 : 11,
        fullCube: true,
        shape: BlockShape.fullCube,
        note: 'The edge `state` and the multi-block size come from the block entity (not available).',
      ),
    for (final advanced in [false, true])
      CcBlockSpec(
        name: advanced ? 'wireless_modem_advanced' : 'wireless_modem_normal',
        javaClass: 'WirelessModemBlock (DirectionalBlock, SimpleWaterloggedBlock), strength(2), MapColor.${advanced ? 'GOLD' : 'STONE'}',
        item: advanced ? 'wireless_modem_advanced' : 'wireless_modem_normal',
        properties: [_facingAll, const BlockProperty.boolean('on'), _waterlogged],
        defaultState: const {'facing': 'north', 'on': 'false', 'waterlogged': 'false'},
        // WirelessModemBlock.getStateForPlacement: the opposite of the clicked face, and the fluid.
        placement: const [
          PlacementRule.clickedFace('facing', opposite: true),
          PlacementRule.inWater('waterlogged'),
        ],
        expectedStates: 24,
        hardness: 2,
        blastResistance: 2,
        mapColor: advanced ? 30 : 11,
        fullCube: false,
        // The shape depends on `facing` in Java (one plate); the host has one
        // shape for all states, so this is the union of the six plates.
        shape: BlockShape.boxes(_modemPlates),
        note: 'Shape: union of the six plates (Java: the one plate of `facing`).',
      ),
    CcBlockSpec(
      name: 'wired_modem_full',
      javaClass: 'WiredModemFullBlock, strength(1.5), MapColor.STONE',
      item: 'wired_modem_full',
      properties: [const BlockProperty.boolean('modem'), const BlockProperty.boolean('peripheral')],
      defaultState: const {'modem': 'false', 'peripheral': 'false'},
      expectedStates: 4,
      hardness: 1.5,
      blastResistance: 1.5,
      mapColor: 11,
      fullCube: true,
      shape: BlockShape.fullCube,
    ),
    CcBlockSpec(
      name: 'cable',
      javaClass: 'CableBlock (SimpleWaterloggedBlock), strength(1.5), MapColor.STONE',
      // `CableBlockItem.Cable` places a cable (state `cable` = true); the other
      // item, `wired_modem`, places a modem on a cable block, which needs the
      // `cable` = false states, see [hostFixed].
      item: 'cable',
      properties: [
        BlockProperty.enumeration('modem', cableModemVariants),
        const BlockProperty.boolean('cable'),
        const BlockProperty.boolean('north'),
        const BlockProperty.boolean('south'),
        const BlockProperty.boolean('east'),
        const BlockProperty.boolean('west'),
        const BlockProperty.boolean('up'),
        const BlockProperty.boolean('down'),
        _waterlogged,
      ],
      defaultState: const {
        'modem': 'none',
        'cable': 'false',
        'north': 'false',
        'south': 'false',
        'east': 'false',
        'west': 'false',
        'up': 'false',
        'down': 'false',
        'waterlogged': 'false',
      },
      expectedStates: 6400,
      hardness: 1.5,
      blastResistance: 1.5,
      mapColor: 11,
      fullCube: false,
      // The shape of Java depends on the sides and the modem; this is the
      // largest shape any state has: the core, six arms and six modem plates.
      shape: _plus,
      connectRules: [
        // CableBlock.doesConnectVisually: a side is `true` when a wired element
        // (a cable or a full wired modem) is next to it. The tag is
        // `computercraft:wired_modem` (cable, wired_modem_full).
        for (final side in ConnectDirection.values)
          ConnectRule(property: side.name, direction: side, target: const ConnectTarget.tag('computercraft:wired_modem')),
      ],
      // 6400 states do not fit the host's 4096. `cable` is the first property
      // by name, so with it fixed to `true` (index 0) the remaining 3200
      // states have exactly the client's ids 0 to 3199: a cable, with or
      // without a modem, in every shape. The 3200 states with `cable` =
      // false (a modem alone, from the `wired_modem` item) are missing.
      hostFixed: const {'cable': 'true'},
      note: 'Needs a host limit of at least 6400 states per block; until then only the states with cable=true exist.',
    ),
    CcBlockSpec(
      name: 'lectern',
      javaClass: 'CustomLecternBlock (LecternBlock), copy of the vanilla lectern',
      // No item: the block replaces a vanilla lectern when a printout or
      // pocket computer is put on it (CustomLecternBlock.replaceLectern).
      item: null,
      properties: [_facing, const BlockProperty.boolean('has_book'), const BlockProperty.boolean('powered')],
      defaultState: const {'facing': 'north', 'has_book': 'true', 'powered': 'false'},
      expectedStates: 16,
      hardness: 2.5,
      blastResistance: 2.5,
      mapColor: 13,
      soundType: 'wood',
      fullCube: false,
      // LecternBlock's base, post and a top plate; the slanted top is not
      // modelled. Approximate (the vanilla shape is not read from source here).
      shape: BlockShape.boxes(const [
        BlockBox(0, 0, 0, 1, 0.125, 1),
        BlockBox(0.25, 0.125, 0.25, 0.75, 0.875, 0.75),
        BlockBox(0, 0.75, 0, 1, 1, 1),
      ]),
      // The loot table is the vanilla lectern's plus the book, a block entity
      // matter.
      drops: BlockDrops.nothing,
      note: 'Strength, sound and map colour of the vanilla lectern (2.5, wood, WOOD): from memory of vanilla, not read from source.',
    ),
    CcBlockSpec(
      name: 'redstone_relay',
      javaClass: 'RedstoneRelayBlock (HorizontalDirectionalBlock), strength(2), MapColor.STONE',
      item: 'redstone_relay',
      properties: [_facing],
      // RedstoneRelayBlock.getStateForPlacement: `getHorizontalDirection()` (not the opposite).
      placement: const [PlacementRule.horizontalFacing('facing')],
      defaultState: const {'facing': 'north'},
      expectedStates: 4,
      hardness: 2,
      blastResistance: 2,
      mapColor: 11,
      fullCube: true,
      shape: BlockShape.fullCube,
    ),
  ];

  /// The block tags CC's data puts its blocks in, name to block names (paths).
  /// `minecraft:mineable/pickaxe`, `mineable/axe` and `wither_immune` are
  /// extensions of vanilla tags; the `computercraft:` ones are the mod's own.
  static const Map<String, List<String>> tags = {
    'minecraft:mineable/pickaxe': [
      'computer_normal',
      'computer_advanced',
      'turtle_normal',
      'turtle_advanced',
      'speaker',
      'disk_drive',
      'printer',
      'monitor_normal',
      'monitor_advanced',
      'wireless_modem_normal',
      'wireless_modem_advanced',
      'wired_modem_full',
      'cable',
      'redstone_relay',
    ],
    'minecraft:mineable/axe': ['lectern'],
    'minecraft:wither_immune': ['computer_command'],
    'computercraft:computer': ['computer_normal', 'computer_advanced', 'computer_command'],
    'computercraft:monitor': ['monitor_normal', 'monitor_advanced'],
    'computercraft:turtle': ['turtle_normal', 'turtle_advanced'],
    'computercraft:wired_modem': ['cable', 'wired_modem_full'],
  };

  /// The number of block states of the client (Java's), 6940.
  static int get totalStates => all.fold(0, (sum, block) => sum + block.javaStateCount);

  /// Builds the registration plan for a host that allows [maxStatesPerBlock]
  /// states per block.
  ///
  /// The blocks are registered in [all] order and a block's states follow the
  /// previous block's directly, so a block can only be numbered like the
  /// client's if every block before it has all its states. A block that does
  /// not fit gets its [CcBlockSpec.hostFixed] properties left out (only the
  /// states that still have the client's ids remain) and ends the plan: the
  /// blocks after it would start at the wrong state id and are left out.
  ///
  /// Throws a [StateError] if the data is inconsistent (a state count that
  /// differs from the hand-counted one, or a reduction that would renumber
  /// states).
  static List<CcBlockPlan> plan({int maxStatesPerBlock = BlockRegistryChecks.maxStatesPerBlock}) {
    final plans = <CcBlockPlan>[];
    for (final spec in all) {
      final full = spec.definition();
      if (full.stateCount != spec.expectedStates) {
        throw StateError(
          '${spec.key}: the properties give ${full.stateCount} states, CC: Tweaked has ${spec.expectedStates} (${spec.javaClass}).',
        );
      }
      var omitted = <String>{};
      var definition = full;
      if (full.stateCount > maxStatesPerBlock) {
        omitted = spec.hostFixed.keys.toSet();
        if (omitted.isEmpty) {
          throw StateError('${spec.key} has ${full.stateCount} states, the host allows $maxStatesPerBlock, and no property can be left out.');
        }
        definition = spec.definition(without: omitted);
        _checkReduction(spec, definition, omitted, maxStatesPerBlock);
      }
      plans.add(CcBlockPlan(spec, definition, omitted));
      if (omitted.isNotEmpty) break;
    }
    return plans;
  }

  static void _checkReduction(CcBlockSpec spec, BlockDefinition reduced, Set<String> omitted, int maxStates) {
    if (reduced.stateCount > maxStates) {
      throw StateError('${spec.key}: ${reduced.stateCount} states even without ${omitted.join(', ')} (limit $maxStates).');
    }
    final sorted = spec.definition().layout.propertyNames;
    for (var i = 0; i < omitted.length; i++) {
      if (!omitted.contains(sorted[i])) {
        throw StateError('${spec.key}: ${omitted.join(', ')} are not the first properties by name (${sorted.take(omitted.length).join(', ')}): leaving them out would renumber the states.');
      }
    }
    for (final entry in spec.hostFixed.entries) {
      final property = spec.properties.firstWhere((p) => p.name == entry.key);
      if (property.valueIndex(entry.value) != 0) {
        throw StateError('${spec.key}: `${entry.key}` must be kept at its first value (${property.values.first}), not ${entry.value}.');
      }
    }
  }

  /// The block tags for [plans], restricted to the blocks that are registered.
  static Map<String, List<String>> tagsFor(List<CcBlockPlan> plans) {
    final registered = {for (final p in plans) p.spec.name};
    return {
      for (final e in tags.entries)
        if (e.value.any(registered.contains))
          e.key: [
            for (final name in e.value)
              if (registered.contains(name)) 'computercraft:$name',
          ],
    };
  }
}
