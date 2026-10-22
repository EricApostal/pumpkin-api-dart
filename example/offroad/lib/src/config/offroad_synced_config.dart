// `offroad-synced.toml`: the mod's SYNCED server config, as the NeoForge
// handshake carries it to clients (`neoforge:config_file`).
//
// The client parses this body into the mod's `ModConfigSpec`; until it arrives
// every `ConfigValue.get()` of the file throws `IllegalStateException: Cannot get
// config value before config is loaded`. Offroad's borehead bearing is an
// `IRotate` block, so Create's `KineticStats` asks `BlockStressValues
// .getImpact(block)` for it, and the provider Offroad registers is
// `OffroadStress::getImpact` (`NeoForgeOffroadConfigService.java:63`): hovering
// that item on a client the file was never sent to crashes the game. The Java
// server sends it (`ConfigSync.syncAllConfigs`), and so must the port.
//
// The paths are the Java ones (`OffroadServer`, `OffroadBlockConfigs`,
// `OffroadStress`): the stress table is `kinetics.stressValues.v2`, because
// `CStress.getName()` is `"stressValues.v" + VERSION`.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/infrastructure/config/synced_toml.dart';

import 'offroad_config.dart';

/// The file name: `ConfigTracker.defaultConfigName(SYNCED, "offroad")`, the name
/// the client's own `config/` directory carries.
const String offroadSyncedConfigFile = 'offroad-synced.toml';

/// Renders [server] as the body of [offroadSyncedConfigFile].
String offroadSyncedToml(OffroadServerConfig server) {
  final toml = SyncedToml();

  final blocks = server.blocks;
  toml.table('blocks');
  toml.value('borehead_bearing_search_radius', blocks.boreheadBearingSearchRadius);
  toml.value('borehead_bearing_stall_recovery_ticks', blocks.boreheadBearingStallRecoveryTicks);
  toml.value('borehead_bearing_stalling_enabled', blocks.boreheadBearingStallingEnabled);
  toml.value('borehead_bearing_rotation_divisor', blocks.boreheadBearingRotationDivisor);

  // Offroad generates no stress, so the Java `capacity` table stays empty and
  // there is nothing to send for it.
  final stress = server.kinetics.stress;
  if (stress.impacts.isNotEmpty) {
    toml.table('kinetics.stressValues.v2.impact');
    for (final entry in stress.impacts.entries) {
      toml.value(entry.key, entry.value);
    }
  }

  return toml.toString();
}
