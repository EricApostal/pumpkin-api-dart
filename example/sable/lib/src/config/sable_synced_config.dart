// `sable-synced.toml`: the mod's SYNCED server config, as the NeoForge handshake
// carries it to clients (`neoforge:config_file`).
//
// The client parses this body into the mod's `ModConfigSpec`; until it arrives
// every read of the file throws `IllegalStateException: Cannot get config value
// before config is loaded`. Sable reads `SUB_LEVEL_SUBSTEPS_PER_TICK` on the
// client too (`PhysicsConfigData.updateFromConfig`, from
// `SubLevelPhysicsSystem`), and the Java server sends the file
// (`ConfigSync.syncAllConfigs` sends every SYNCED config of every installed mod),
// so the port sends it as well.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/infrastructure/config/synced_toml.dart';

import '../sublevel/system/sable_server_config.dart';

/// The file name: `ConfigTracker.defaultConfigName(SYNCED, "sable")`, the name
/// the client's own `config/` directory carries.
const String sableSyncedConfigFile = 'sable-synced.toml';

/// Renders [config] as the body of [sableSyncedConfigFile].
String sableSyncedToml(SableServerConfig config) {
  final toml = SyncedToml();
  toml.value('sub_level_substeps_per_tick', config.subLevelSubstepsPerTick);
  toml.value('sub_level_storage_pruning', config.subLevelStoragePruning);
  return toml.toString();
}
