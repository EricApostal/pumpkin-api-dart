/// The plugin entry point of Sable (the component's `main`).
///
/// Kept apart from `sable.dart` because the plugin needs `pumpkin_api`, which
/// the VM tests must not load.
library;

export 'sable.dart';
export 'sable_channels.dart';
export 'src/plugin/sable_plugin.dart';
