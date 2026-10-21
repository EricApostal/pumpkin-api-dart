// The registration order and the state properties of the Java mod, key by key.
//
// NeoForge numbers registry entries by position, so a client that has the Java
// mods installed numbers `aeronautics:white_envelope` the same only if the
// entries before it are the same. The lists below are the Java
// field-initialiser order of `index/AeroBlocks`, `index/AeroItems`,
// `index/AeroBlockEntityTypes` and `index/AeroEntityTypes`;
// `registerAeronautics` pins them with `CreateRegistry.useOrder`.
//
// Pure: no host imports, so the VM tests can check the tables. The module checks
// what it builds against the state property table at load
// (`aeronautics_module.dart`): `forwards` in `CreateRegistry`, `CreateBlock` and
// `CreateProps` import the wasm-only `package:pumpkin_api/pumpkin_api.dart`, so
// no VM test can read a `CreateBlock`.
//
// Java: `dev.eriksonn.aeronautics.index.*`
library;

/// `DyeColor.values()` order: the order every dyed family expands in.
const List<String> aeroDyeColorOrder = [
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

/// The Java order of everything Aeronautics registers.
abstract final class AeroJavaOrder {
  /// The block keys in registration order (43).
  ///
  /// `index/AeroBlocks.java:73-413`: `white_envelope` is registered on its own
  /// before the dyed list, so the list starts with it and the other fifteen
  /// follow; then the encased shafts (all sixteen), then the singles, then
  /// `levitite_blend`.
  ///
  /// `aeronautics:levitite_blend` is **loader-side** in Java (`AeroFluidsNeoForge`,
  /// touched through `NeoForgeAeroLevititeService`), so its position is not
  /// derivable from `AeroBlocks`; it is pinned last, after `AeroBlocks.init()` and
  /// `AeroFluidsNeoForge.init()` have both run (`AeronauticsNeoForge.java:22-23`).
  static final List<String> blocks = [
    'aeronautics:white_envelope', // :74
    for (final colour in aeroDyeColorOrder)
      if (colour != 'white') 'aeronautics:${colour}_envelope', // :107-143
    for (final colour in aeroDyeColorOrder)
      'aeronautics:${colour}_envelope_encased_shaft', // :145-183
    'aeronautics:adjustable_burner', // :185
    'aeronautics:steam_vent', // :217
    'aeronautics:propeller_bearing', // :242
    'aeronautics:gyroscopic_propeller_bearing', // :267
    'aeronautics:smart_propeller', // :293
    'aeronautics:andesite_propeller', // :321
    'aeronautics:wooden_propeller', // :349
    'aeronautics:mounted_potato_cannon', // :367
    'aeronautics:levitite', // :382
    'aeronautics:pearlescent_levitite', // :402
    // Pinned: registered by the loader half, not by `AeroBlocks`.
    'aeronautics:levitite_blend',
  ];

  /// The item keys in registration order (46).
  ///
  /// A block item is registered inside its block's builder, so the block items
  /// come first, in block order (`levitite_blend` has none: the fluid block is
  /// not an item). `AeroItems` follows: goggles (`AeroItems.java:21`), the disc
  /// (`:40`), the powder (`:55`). The bucket belongs to the fluid, which
  /// `AeroFluidsNeoForge.init()` registers after `Aeronautics.init()`.
  static final List<String> items = [
    for (final key in blocks)
      if (key != 'aeronautics:levitite_blend') key,
    'aeronautics:aviators_goggles',
    'aeronautics:music_disc_cloud_skipper',
    'aeronautics:end_stone_powder',
    'aeronautics:levitite_blend_bucket',
  ];

  /// The block entity type keys in registration order (9) —
  /// `index/AeroBlockEntityTypes.java:35,40,45,51,57,63,69,75,80`.
  static const List<String> blockEntityTypes = [
    'aeronautics:steam_vent',
    'aeronautics:adjustable_burner',
    'aeronautics:propeller_bearing',
    'aeronautics:gyroscopic_propeller_bearing',
    'aeronautics:envelope_encased_shaft',
    'aeronautics:andesite_propeller',
    'aeronautics:wooden_propeller',
    'aeronautics:smart_propeller',
    'aeronautics:mounted_potato_cannon',
  ];

  /// The entity type keys in registration order (2) —
  /// `index/AeroEntityTypes.java:23,37`.
  static const List<String> entityTypes = [
    'aeronautics:propeller_bearing_contraption',
    'aeronautics:gust',
  ];

  /// The data component keys in registration order (2) —
  /// `index/AeroDataComponents.java:16-20`.
  static const List<String> dataComponents = ['aeronautics:levitating', 'aeronautics:converter'];

  /// `aeronautics:lifting_gas_type` — `index/AeroLiftingGasTypes.java:16-17`.
  static const String liftingGasTypeRegistry = 'aeronautics:lifting_gas_type';
  static const List<String> liftingGasTypes = ['aeronautics:default', 'aeronautics:steam'];

  /// `aeronautics:levitite_crystal_propagation_context` —
  /// `index/AeroLevititeBlendPropagationContexts.java:15-16`.
  static const String crystallizationContextRegistry = 'aeronautics:levitite_crystal_propagation_context';
  static const List<String> crystallizationContexts = ['aeronautics:standard', 'aeronautics:soul'];

  /// The fluid keys of `aeronautics:levitite_blend`
  /// (`AeroFluidsNeoForge.java:24-52`). `standardFluid` registers the still
  /// fluid, its flowing variant and the block, all under the one path.
  static const String levititeBlendStill = 'aeronautics:levitite_blend';
  static const String levititeBlendFlowing = 'aeronautics:levitite_blend_flowing';
  static const String levititeBlendBucket = 'aeronautics:levitite_blend_bucket';

  /// The state properties of every block of [blocks]: `name -> values`, the
  /// values in `Property.getPossibleValues()` order.
  ///
  /// A block's number of states is the product of the value counts, and the base
  /// state id of the next block starts right after them, so a property the Java
  /// does not have (or one this port forgot) moves every state id after the
  /// block. The names are what the module checks at load; the values of the
  /// six-valued `facing` are the Java's (`BlockStateProperties.java:53-55`),
  /// which `CreateProps.facing` still spells in the `Direction` enum order.
  static final Map<String, Map<String, List<String>>> stateProperties = {
    // `EnvelopeBlock extends CasingBlock extends Block`
    // (`EnvelopeBlock.java:37`, `CasingBlock.java:9`): no state of its own.
    for (final colour in aeroDyeColorOrder) 'aeronautics:${colour}_envelope': {},
    // `EnvelopeEncasedShaftBlock extends EncasedShaftBlock` (`:35`) ->
    // `RotatedPillarKineticBlock.AXIS` (`RotatedPillarKineticBlock.java:16`):
    // x, y, z.
    for (final colour in aeroDyeColorOrder)
      'aeronautics:${colour}_envelope_encased_shaft': {'axis': ['x', 'y', 'z']},
    // `HotAirBurnerBlock extends Block` and adds `POWERED, VARIANT`
    // (`HotAirBurnerBlock.java:51-52,103-105`), variants `fire` and `soulful`
    // (`:168-171`), `POWERED` first: 4 states. It has no facing and no `lit`.
    'aeronautics:adjustable_burner': {
      'powered': ['true', 'false'],
      'variant': ['fire', 'soulful'],
    },
    // `SteamVentBlock extends Block` and adds `POWERED, WATERLOGGED, VARIANT,
    // FACING` (`SteamVentBlock.java:47,60`), variants `gold` and `iron`
    // (`:156-158`): 4 x 2 x 2 x 2 = 32 states.
    'aeronautics:steam_vent': {
      'facing': ['north', 'south', 'west', 'east'],
      'powered': ['true', 'false'],
      'variant': ['gold', 'iron'],
      'waterlogged': ['true', 'false'],
    },
    // `PropellerBearingBlock extends BearingBlock` (`PropellerBearingBlock.java:23`)
    // -> `DirectionalKineticBlock.FACING` (`BearingBlock.java:14`), 6 states.
    'aeronautics:propeller_bearing': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
    },
    // `GyroscopicPropellerBearingBlock extends BearingBlock` (`:24`), 6 states.
    'aeronautics:gyroscopic_propeller_bearing': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
    },
    // `SmartPropellerBlock extends HorizontalAxisKineticBlock` (`:24`):
    // `HORIZONTAL_AXIS` (`HorizontalAxisKineticBlock.java:20`, x and z), then
    // `REVERSED, CEILING` (`:35-36`): 2 x 2 x 2 = 8 states.
    'aeronautics:smart_propeller': {
      'ceiling': ['true', 'false'],
      'horizontal_axis': ['x', 'z'],
      'reversed': ['true', 'false'],
    },
    // `AndesitePropellerBlock`/`WoodenPropellerBlock extend BasePropellerBlock`
    // (`BasePropellerBlock.java:23`) -> `DirectionalKineticBlock.FACING` plus
    // `REVERSED` (`:34`): 6 x 2 = 12 states.
    'aeronautics:andesite_propeller': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'reversed': ['true', 'false'],
    },
    'aeronautics:wooden_propeller': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'reversed': ['true', 'false'],
    },
    // `MountedPotatoCannonBlock extends DirectionalAxisKineticBlock` (`:31`):
    // `AXIS_ALONG_FIRST_COORDINATE` (`DirectionalAxisKineticBlock.java:29`) and
    // `FACING`, then `POWERED, BLOCKED` (`:108`): 2 x 6 x 2 x 2 = 48 states.
    'aeronautics:mounted_potato_cannon': {
      'axis_along_first_coordinate': ['true', 'false'],
      'blocked': ['true', 'false'],
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'powered': ['true', 'false'],
    },
    // `Block::new` (`AeroBlocks.java:382,402`): no state.
    'aeronautics:levitite': {},
    'aeronautics:pearlescent_levitite': {},
    // The fluid block of `levitite_blend` (`AeroFluidsNeoForge.java:24-52`):
    // a liquid block, no state of its own.
    'aeronautics:levitite_blend': {},
  };

  /// The state properties of [key], or `null` for a key the Java table does not
  /// know.
  static Map<String, List<String>>? propertiesOf(String key) => stateProperties[key];
}