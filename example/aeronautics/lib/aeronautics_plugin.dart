/// The plugin side of Aeronautics: the block entities, the blocks, the module
/// and the world adapters. Imports `pumpkin_api`, so it only runs as a wasm
/// component.
library;

export 'aeronautics.dart';
export 'src/aeronautics_hooks.dart';
export 'src/aeronautics_module.dart';
export 'src/content/blocks/hot_air/envelope_blocks.dart';
export 'src/content/blocks/hot_air/hot_air_burner_block.dart';
export 'src/content/blocks/hot_air/steam_vent.dart';
export 'src/content/blocks/levitite/levitite_blocks.dart';
export 'src/content/blocks/mounted_potato_cannon/mounted_potato_cannon.dart';
export 'src/content/blocks/propeller/gyroscopic_propeller_bearing_block.dart';
export 'src/content/blocks/propeller/propeller_bearing_block.dart';
export 'src/content/blocks/propeller/propeller_bearing_contraption_entity.dart';
export 'src/content/blocks/propeller/small_propeller_blocks.dart';
export 'src/content/components/converter.dart';
export 'src/content/components/levitating.dart';
export 'src/content/items/aero_items.dart';
export 'src/content/items/item_behaviour.dart';
export 'src/host/host_propeller_push_world.dart';
export 'src/host/world_balloon_world.dart';
export 'src/index/aero_registry.dart';
export 'src/levitite/levitite_crystallization.dart';
export 'src/plugin/aeronautics_addon.dart';
