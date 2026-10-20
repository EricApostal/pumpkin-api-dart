/// The Aeronautics port: the pure model of propellers, hot-air balloons and the
/// envelope blocks.
///
/// Everything exported here runs on the Dart VM (no host bindings), so the
/// tests use it directly. The block entities, the module and the world adapters
/// are in `aeronautics_plugin.dart`.
library;

export 'src/config/aero_config.dart';
export 'src/content/envelope_dye.dart';
export 'src/hot_air/balloon.dart';
export 'src/hot_air/balloon_builder.dart';
export 'src/hot_air/balloon_layer_data.dart';
export 'src/hot_air/balloon_layer_graph.dart';
export 'src/hot_air/balloon_map.dart';
export 'src/hot_air/balloon_world.dart';
export 'src/hot_air/lifting_gas.dart';
export 'src/hot_air/lifting_gas_provider.dart';
export 'src/hot_air/server_balloon.dart';
export 'src/propeller/geometry.dart';
export 'src/propeller/gyroscopic_tilt.dart';
export 'src/propeller/propeller_actor_behaviour.dart';
export 'src/propeller/propeller_bearing.dart';
export 'src/propeller/small_propeller.dart';
export 'src/simulated_bridge.dart';
