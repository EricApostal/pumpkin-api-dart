/// The plugin entry point of Simulated (the component's `main`).
///
/// Kept apart from `simulated.dart` because the plugin needs `pumpkin_api`,
/// which the VM tests must not load.
library;

export 'src/host/pumpkin_host.dart';
export 'src/index/sim_blocks.dart';
export 'src/index/sim_items.dart';
export 'src/index/sim_registry.dart';
export 'src/plugin/simulated_plugin.dart';
