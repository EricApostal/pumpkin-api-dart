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

/// A still fluid of the mod, its flowing variant, and what the pair owns.
///
/// Registrate's `FluidBuilder` registers all of it from one `standardFluid`
/// call (`FluidBuilder.java:597-614`), so the port keeps them together too: the
/// host rejects a still fluid whose flowing variant never registers
/// (`FluidRegistrationError::UnknownFluid`).
final class AeroFluidPair {
  const AeroFluidPair({
    required this.still,
    required this.flowing,
    required this.block,
    required this.bucket,
  });

  /// The source fluid, registered first.
  final String still;

  /// The flowing variant, `flowing_<path of still>` in Java.
  final String flowing;

  /// The `LiquidBlock` holding the fluid; it belongs to the source entry.
  final String block;

  /// The bucket item, `<name>_bucket`.
  final String bucket;
}

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
  /// (`AeroFluidsNeoForge.java:24-52`).
  ///
  /// `standardFluid("levitite_blend", ...)` (`CreateRegistrate.java:241-249`) is
  /// Registrate's `fluid(name, ...)`: **one** builder registering the source as
  /// `name` and the flowing variant as `flowing_<name>`. The builder's own entry
  /// is `"flowing_" + name` (`FluidBuilder.java:291`), the source is accepted
  /// into the fluid registry first (`:609`) and the flowing entry last (`:614`).
  /// Create's generated data spells the same names (`create:flowing_honey`,
  /// `Create/src/generated/resources/data/c/tags/fluid/honey.json:3`), as does
  /// vanilla (`minecraft:flowing_water`).
  ///
  /// What the pair owns, all from that one call: the `LiquidBlock` named after
  /// the source (`FluidBuilder.java:426`) and the `<name>_bucket` item
  /// (`:293,494`). The flowing entry has no block and no bucket of its own.
  static const String levititeBlendStill = 'aeronautics:levitite_blend';
  static const String levititeBlendFlowing = 'aeronautics:flowing_levitite_blend';
  static const String levititeBlendBucket = 'aeronautics:levitite_blend_bucket';

  /// The fluid entries in Java registration (and so id) order: each source
  /// before its flowing variant (`FluidBuilder.java:597-614`).
  static const List<String> fluidOrder = [levititeBlendStill, levititeBlendFlowing];

  /// The still fluids of the mod with their flowing variant and the block and
  /// bucket the pair owns, in [fluidOrder]. `registerAeronautics` registers from
  /// this table, so a still fluid cannot be registered without its flowing
  /// entry: the host rejects one that never registers
  /// (`FluidRegistrationError::UnknownFluid`, `fluid_registry.rs:279-287`).
  static const List<AeroFluidPair> fluidPairs = [
    AeroFluidPair(
      still: levititeBlendStill,
      flowing: levititeBlendFlowing,
      block: levititeBlendStill,
      bucket: levititeBlendBucket,
    ),
  ];

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
    // The fluid block of `levitite_blend`, a vanilla `LiquidBlock`
    // (`FluidBuilder.java:405-426,601`, `AeroFluidsNeoForge.java:24`): its one
    // property is `LEVEL` (`LiquidBlock.java:39,225`), an int from 0 to 15
    // (`BlockStateProperties.java:116`), default 0 (`LiquidBlock.java:58`) -- 16
    // states, not one. It is the last block of [blocks], so only its own states
    // move, but the count has to be right before anything is appended after it.
    'aeronautics:levitite_blend': {
      'level': ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15'],
    },
  };

  /// The state properties of [key], or `null` for a key the Java table does not
  /// know.
  static Map<String, List<String>>? propertiesOf(String key) => stateProperties[key];
}

/// What is wrong with a set of fluid registrations, `[]` when nothing is.
///
/// [flowingVariantOf] maps every registered fluid key to the flowing variant it
/// names (`null` for a fluid that names none), in registration (id) order.
///
/// The host rejects a still fluid whose variant never registers
/// (`FluidRegistrationError::UnknownFluid`, `fluid_registry.rs:279-287`) and
/// numbers fluids in registration order, so the two entries of a pair must both
/// be there, the flowing one after the still one (`FluidBuilder.java:597-614`).
/// A VM test can only read this module's own table; the module calls this with
/// the real registry at load (`aeronautics_module.dart`), which is what makes
/// the omission impossible rather than merely tested.
List<String> fluidPairProblems(Map<String, String?> flowingVariantOf) {
  final keys = flowingVariantOf.keys.toList();
  final problems = <String>[];
  for (final entry in flowingVariantOf.entries) {
    final flowing = entry.value;
    if (flowing == null) continue;
    final index = keys.indexOf(flowing);
    if (index < 0) {
      problems.add('`${entry.key}` names flowing variant `$flowing`, which is not registered');
      continue;
    }
    final still = keys.indexOf(entry.key);
    if (index < still) {
      problems.add('`$flowing` is registered before `${entry.key}`, but Java registers the source first');
    }
  }
  return problems;
}