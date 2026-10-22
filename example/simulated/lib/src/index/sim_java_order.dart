// The registration order of the Java mod, key by key.
//
// NeoForge numbers registry entries by position, so a client that has the Java
// mods installed numbers `simulated:spring` the same only if the entries before
// it are the same. The lists below are the Java field-initialiser order of
// `index/SimBlocks`, `index/SimItems` and `index/SimBlockEntityTypes`, and each
// entry names the line it comes from.
//
// `SimRegistry.register` pins them with `CreateRegistry.useOrder`, so the order
// this port happens to declare its content in does not matter: the ids follow
// these lists. Content the port has not translated yet is simply not registered,
// and `SimRegistry` reports the gap (`OrderReport.missing`) instead of silently
// numbering the rest as if it were complete.
//
// `Simulated.init()` (`Simulated.java:42-44`) touches `SimBlocks`, then
// `SimItems`, then `SimBlockEntityTypes`, and Registrate registers a block's
// item inside the block's builder -- so the item order is the block items in
// block order, then the standalone items of `SimItems`.
//
// Pure: no host imports, so the VM tests can check the tables.
//
// Java: `dev.simulated_team.simulated.index.{SimBlocks,SimItems,SimBlockEntityTypes}`
library;

import 'sim_items.dart';

/// `DyeColor.values()` order: the order every dyed family expands in.
const List<String> simDyeColors = [
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

/// The Java registration order, as the tables `SimRegistry` pins.
abstract final class SimJavaOrder {
  /// The blocks, in `SimBlocks` field-initialiser order (95).
  ///
  /// `SimBlocks.java:100-855`: one entry per `REGISTRATE.block(...)` call, with
  /// the dyed families (`DYED_HANDLES`, `PORTABLE_ENGINES`,
  /// `DYED_SYMMETRIC_SAILS`, `NAMEPLATES`) expanded in `DyeColor.values()`
  /// order. `DYED_SYMMETRIC_SAILS` reuses `WHITE_SYMMETRIC_SAIL` for white
  /// (`SimBlocks.java:779-783`), so white is listed once, before the family.
  static final List<String> blocks = [
    'simulated:physics_assembler', // :100
    'simulated:swivel_bearing', // :118
    'simulated:swivel_bearing_link_block', // :141
    'simulated:merging_glue', // :153
    'simulated:rope_winch', // :164
    'simulated:rope_connector', // :186
    'simulated:iron_handle', // :204
    'simulated:copper_handle', // :221
    // `DYED_HANDLES` (`:231-241`), in `DyeColor.values()` order.
    for (final colour in simDyeColors) 'simulated:${colour}_handle',
    'simulated:directional_gearshift', // :243
    'simulated:torsion_spring', // :263
    'simulated:auger_shaft', // :283
    'simulated:auger_cog', // :308
    // `PORTABLE_ENGINES` (`:327-353`), in `DyeColor.values()` order.
    for (final colour in simDyeColors) 'simulated:${colour}_portable_engine',
    'simulated:laser_pointer', // :377
    'simulated:laser_sensor', // :396
    'simulated:velocity_sensor', // :417
    'simulated:altitude_sensor', // :437
    'simulated:gimbal_sensor', // :461
    'simulated:navigation_table', // :485
    'simulated:optical_sensor', // :505
    'simulated:docking_connector', // :526
    'simulated:paired_docking_connector', // :544
    'simulated:analog_transmission', // :558
    'simulated:steering_wheel', // :581
    'simulated:throttle_lever', // :605
    'simulated:linked_typewriter', // :622
    'simulated:directional_linked_receiver', // :635
    'simulated:modulating_linked_receiver', // :654
    'simulated:redstone_accumulator', // :673
    'simulated:redstone_inductor', // :693
    'simulated:redstone_magnet', // :732
    'simulated:white_symmetric_sail', // :750
    // `DYED_SYMMETRIC_SAILS` (`:779-800`); white is the block above.
    for (final colour in simDyeColors)
      if (colour != 'white') 'simulated:${colour}_symmetric_sail',
    // `NAMEPLATES` (`:801-841`), in `DyeColor.values()` order.
    for (final colour in simDyeColors) 'simulated:${colour}_nameplate',
    'simulated:spring', // :843
  ];

  /// The blocks that register **no** item.
  ///
  /// `SimBlocks.java`: `swivel_bearing_link_block` drops the bearing (`:147`),
  /// `merging_glue` has no loot table (`:158-162`), `paired_docking_connector`
  /// has none either (`:552-557`), the fifteen dyed sails drop the white sail
  /// (`:779-800`), and `spring`'s item is the standalone `SimItems.SPRING`
  /// (`:853-855`).
  static const Set<String> blocksWithoutItem = {
    'simulated:swivel_bearing_link_block',
    'simulated:merging_glue',
    'simulated:paired_docking_connector',
    'simulated:orange_symmetric_sail',
    'simulated:magenta_symmetric_sail',
    'simulated:light_blue_symmetric_sail',
    'simulated:yellow_symmetric_sail',
    'simulated:lime_symmetric_sail',
    'simulated:pink_symmetric_sail',
    'simulated:gray_symmetric_sail',
    'simulated:light_gray_symmetric_sail',
    'simulated:cyan_symmetric_sail',
    'simulated:purple_symmetric_sail',
    'simulated:blue_symmetric_sail',
    'simulated:brown_symmetric_sail',
    'simulated:green_symmetric_sail',
    'simulated:red_symmetric_sail',
    'simulated:black_symmetric_sail',
    'simulated:spring',
  };

  /// The items, in registration order (86).
  ///
  /// A block's item is registered by the block's builder, so the block items
  /// come first, in [blocks] order (`SimBlocks.java`); then the standalone
  /// items of `SimItems` in field order (`SimItems.java:32-108`).
  static final List<String> items = [
    for (final key in blocks)
      if (!blocksWithoutItem.contains(key)) key,
    'simulated:contraption_diagram', // SimItems.java:32
    'simulated:spring', // :41
    'simulated:rope_coupling', // :56
    'simulated:gyroscopic_mechanism', // :62
    'simulated:incomplete_gyroscopic_mechanism', // :66
    'simulated:engine_assembly', // :75
    'simulated:incomplete_engine_assembly', // :77
    'simulated:honey_glue', // :84
    'simulated:creative_physics_staff', // :91
    'simulated:plunger_launcher', // :97
  ];

  /// The block entity types, in `SimBlockEntityTypes` field-initialiser order
  /// (30) — `SimBlockEntityTypes.java:53-278`.
  ///
  /// `simulated:simple` is `SIMPLE_BE` (`:53-58`), the block entity of
  /// `simulated:analog_transmission`. `simulated:ir_sensor` (`:166-170`) is the
  /// block entity of the block `simulated:laser_sensor`: the ids differ, and the
  /// block entity id is the legacy one. The `ABSORBER` entry between
  /// `throttle_lever` and `auger_shaft` is commented out in the Java
  /// (`:237-241`), so it takes no id.
  static const List<String> blockEntityTypes = [
    'simulated:simple', // :53
    'simulated:torsion_spring', // :60
    'simulated:physics_assembler', // :67
    'simulated:rope_winch', // :73
    'simulated:rope_connector', // :79
    'simulated:docking_connector', // :85
    'simulated:altitude_sensor', // :94
    'simulated:gimbal_sensor', // :100
    'simulated:handle', // :107
    'simulated:portable_engine', // :114
    'simulated:swivel_bearing', // :121
    'simulated:steering_wheel', // :128
    'simulated:spring', // :135
    'simulated:swivel_bearing_link_block', // :141
    'simulated:linked_typewriter', // :148
    'simulated:optical_sensor', // :156
    'simulated:laser_pointer', // :161
    'simulated:ir_sensor', // :166
    'simulated:velocity_sensor', // :174
    'simulated:directional_linked_receiver', // :181
    'simulated:nameplate', // :188
    'simulated:modulating_linked_receiver', // :194
    'simulated:redstone_accumulator', // :203
    'simulated:navigation_table', // :209
    'simulated:redstone_inductor', // :217
    'simulated:redstone_magnet', // :224
    'simulated:throttle_lever', // :229
    'simulated:auger_shaft', // :244
    'simulated:merging_glue', // :267
    'simulated:directional_gearshift', // :273
  ];
}

/// What this port actually registers, against the Java order above.
///
/// The port translates a subset of the Java content, so the ids of what it
/// registers are still off by the number of entries the Java has before them
/// (`SimRegistry` reports the gap at load). What these tables pin is that the
/// registered subset is a *subsequence* of the Java order, in the Java order,
/// and that nothing is registered that the Java does not have: a block added in
/// the wrong place, or one that goes missing, fails `SimRegistry.register` and
/// the VM test instead of shifting ids quietly.
///
/// Kept off the host API on purpose: `CreateRegistry` and `CreateBlock` import
/// the wasm-only `package:pumpkin_api/pumpkin_api.dart`, so no VM test can build
/// them. `SimRegistry.register` compares what it builds with these tables.
abstract final class SimPorted {
  /// The items `SimRegistry.register` puts in the registry, in registration
  /// order: the standalone items first (the plugin registers them before the
  /// blocks), then the item of every block of [blocks] that has one.
  ///
  /// The Java order of the *ids* is the other way round -- the block items come
  /// first there, in block order (`Simulated.java:42-43`) -- which `useOrder`
  /// restores.
  static final List<String> items = [
    for (final item in simItems()) item.key,
    for (final key in blocks)
      if (!SimJavaOrder.blocksWithoutItem.contains(key)) key,
  ];

  /// The blocks `simBlocks()` builds, in the Java order (39 of the 95).
  static const List<String> blocks = [
    'simulated:physics_assembler', // SimBlocks.java:100
    'simulated:swivel_bearing', // :118
    'simulated:swivel_bearing_link_block', // :141
    'simulated:torsion_spring', // :263
    // `PORTABLE_ENGINES` (`:327-353`), in `DyeColor.values()` order.
    'simulated:white_portable_engine', // :327
    'simulated:orange_portable_engine',
    'simulated:magenta_portable_engine',
    'simulated:light_blue_portable_engine',
    'simulated:yellow_portable_engine',
    'simulated:lime_portable_engine',
    'simulated:pink_portable_engine',
    'simulated:gray_portable_engine',
    'simulated:light_gray_portable_engine',
    'simulated:cyan_portable_engine',
    'simulated:purple_portable_engine',
    'simulated:blue_portable_engine',
    'simulated:brown_portable_engine',
    'simulated:green_portable_engine',
    'simulated:red_portable_engine',
    'simulated:black_portable_engine',
    'simulated:steering_wheel', // :581
    'simulated:throttle_lever', // :605
    'simulated:white_symmetric_sail', // :750
    'simulated:orange_symmetric_sail', // :779
    'simulated:magenta_symmetric_sail', // :779
    'simulated:light_blue_symmetric_sail', // :779
    'simulated:yellow_symmetric_sail', // :779
    'simulated:lime_symmetric_sail', // :779
    'simulated:pink_symmetric_sail', // :779
    'simulated:gray_symmetric_sail', // :779
    'simulated:light_gray_symmetric_sail', // :779
    'simulated:cyan_symmetric_sail', // :779
    'simulated:purple_symmetric_sail', // :779
    'simulated:blue_symmetric_sail', // :779
    'simulated:brown_symmetric_sail', // :779
    'simulated:green_symmetric_sail', // :779
    'simulated:red_symmetric_sail', // :779
    'simulated:black_symmetric_sail', // :779
    'simulated:spring', // :843
  ];

  /// The block entity types `SimRegistry` registers, in the Java order (8 of the
  /// 30) — `SimBlockEntityTypes.java:60,67,114,121,128,135,141,229`.
  static const List<String> blockEntityTypes = [
    'simulated:torsion_spring',
    'simulated:physics_assembler',
    'simulated:portable_engine', // :114
    'simulated:swivel_bearing',
    'simulated:steering_wheel',
    'simulated:spring',
    'simulated:swivel_bearing_link_block',
    'simulated:throttle_lever',
  ];

  /// The Java state properties of each block in [blocks]: `name -> values`, the
  /// values in `Property.getPossibleValues()` order.
  ///
  /// These are the properties a Java client knows, so they fix how many states
  /// the block has -- `waterlogged` on the assembler and `lit` on the burner of
  /// Aeronautics were twice the states the Java has, and every state id after the
  /// block shifted with them. `SimRegistry` checks the *names* of what it builds
  /// against this table; the values of the six-valued `facing` are the Java's
  /// (`BlockStateProperties.java:53-55`), which `CreateProps.facing` still spells
  /// in the `Direction` enum order.
  static const Map<String, Map<String, List<String>>> stateProperties = {
    // `PhysicsAssemblerBlock extends FaceAttachedHorizontalDirectionalBlock`
    // (`PhysicsAssemblerBlock.java:30`), `builder.add(FACING, FACE)` (`:110-112`):
    // 4 x 3.
    'simulated:physics_assembler': {
      'face': ['floor', 'wall', 'ceiling'],
      'facing': ['north', 'south', 'west', 'east'],
    },
    // `SwivelBearingBlock extends DirectionalKineticBlock` (`:40`), `ASSEMBLED,
    // POWERED` (`:41-42,51-52`): 6 x 2 x 2.
    'simulated:swivel_bearing': {
      'assembled': ['true', 'false'],
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'powered': ['true', 'false'],
    },
    // `SwivelBearingPlateBlock extends DirectionalKineticBlock` (`:26`): `FACING`
    // only, 6.
    'simulated:swivel_bearing_link_block': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
    },
    // `TorsionSpringBlock extends DirectionalKineticBlock` (`:28`), `POWERED`
    // (`:29,37-38`): 6 x 2.
    'simulated:torsion_spring': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'powered': ['true', 'false'],
    },
    // `SteeringWheelBlock extends HorizontalDirectionalBlock` (`:48`),
    // `WATERLOGGED, FACING, ON_FLOOR` (`:133-134`): 4 x 2 x 2.
    'simulated:steering_wheel': {
      'facing': ['north', 'south', 'west', 'east'],
      'on_floor': ['true', 'false'],
      'waterlogged': ['true', 'false'],
    },
    // `ThrottleLeverBlock extends FaceAttachedHorizontalDirectionalBlock` (`:35`),
    // `FACING, FACE, INVERTED` (`:152-153`): 4 x 3 x 2.
    'simulated:throttle_lever': {
      'face': ['floor', 'wall', 'ceiling'],
      'facing': ['north', 'south', 'west', 'east'],
      'inverted': ['true', 'false'],
    },
    // `SymmetricSailBlock extends RotatedPillarBlock` (`:47`): `AXIS`, 3. All
    // sixteen colours share the definition.
    'simulated:white_symmetric_sail': {'axis': ['x', 'y', 'z']},
    // `PortableEngineBlock extends HorizontalKineticBlock` (`:36`),
    // `LIT` added (`:58-62`): 4 x 2. All sixteen colours share the definition.
    'simulated:white_portable_engine': {
      'facing': ['north', 'south', 'west', 'east'],
      'lit': ['true', 'false'],
    },
    // `SpringBlock extends WrenchableDirectionalBlock` (`SpringBlock.java:39`)
    // -> `FACING`, `SIZE` (`:40,48-49`): 6 x 3.
    'simulated:spring': {
      'facing': ['north', 'east', 'south', 'west', 'up', 'down'],
      'size': ['small', 'medium', 'large'],
    },
  };

  /// The state properties of [key]; the fifteen dyed sails share the white one,
  /// and so do the fifteen dyed engines.
  static Map<String, List<String>> propertiesOf(String key) {
    if (key.endsWith('_symmetric_sail')) return stateProperties['simulated:white_symmetric_sail']!;
    if (key.endsWith('_portable_engine')) return stateProperties['simulated:white_portable_engine']!;
    return stateProperties[key]!;
  }
}
