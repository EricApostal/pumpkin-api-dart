/// The Offroad port: the pure model of the mod — the tire data, the wheel mount
/// and borehead bearing state machines, the multi-block mining, the sync
/// payload and the contraption kind.
///
/// Everything exported here runs on the Dart VM (no host bindings), so the tests
/// use it directly. The block entities, the blocks, the registry and the plugin
/// are in `offroad_plugin.dart`.
library;

export 'src/config/offroad_config.dart';
export 'src/content/blocks/borehead_bearing/borehead_bearing_logic.dart';
export 'src/content/blocks/rock_cutting_wheel/rock_cutting_wheel_rotation.dart';
export 'src/content/blocks/wheel_mount/wheel_mount_logic.dart';
export 'src/content/components/tire_like.dart';
export 'src/content/contraptions/borehead_contraption.dart';
export 'src/handlers/multi_mining.dart';
export 'src/index/offroad_ids.dart';
export 'src/network/borehead_sync_packet.dart';
export 'src/network/offroad_channels.dart';

