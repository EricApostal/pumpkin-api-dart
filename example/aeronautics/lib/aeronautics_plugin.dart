/// The plugin side of Aeronautics: the block entities, the blocks, the module
/// and the world adapters. Imports `pumpkin_api`, so it only runs as a wasm
/// component.
library;

export 'aeronautics.dart';
export 'src/aeronautics_hooks.dart';
export 'src/aeronautics_module.dart';
export 'src/content/blocks/hot_air/envelope_blocks.dart';
export 'src/content/blocks/hot_air/hot_air_burner_block.dart';
export 'src/content/blocks/propeller/gyroscopic_propeller_bearing_block.dart';
export 'src/content/blocks/propeller/propeller_bearing_block.dart';
export 'src/content/blocks/propeller/propeller_bearing_contraption_entity.dart';
export 'src/content/blocks/propeller/small_propeller_blocks.dart';
export 'src/host/host_propeller_push_world.dart';
export 'src/host/world_balloon_world.dart';
