// `aeronautics-synced.toml`: the mod's SYNCED server config, as the NeoForge
// handshake carries it to clients (`neoforge:config_file`).
//
// The client parses this body into the mod's `ModConfigSpec`; until it arrives
// every `ConfigValue.get()` of the file throws `IllegalStateException: Cannot get
// config value before config is loaded`. That is not a tooltip-only problem:
// `KineticStats.getKineticStats` asks `BlockStressValues.getImpact`, Aeronautics
// registered `AeroStress::getImpact` as a provider (`NeoForgeAeroConfigService
// .java:60-62`), so hovering an Aeronautics kinetic block on a client the file
// was never sent to crashes the game. The Java server sends it
// (`ConfigSync.syncAllConfigs`), and so must the port.
//
// The paths are the Java ones (`AeroServer`, `AeroPhysics`, `AeroBlockConfigs`),
// not the plugin's JSON layout. A value the port does not model is left out: the
// client then uses its own default, which is the Java default.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/infrastructure/config/synced_toml.dart';

import 'aero_config.dart';

/// The file name: `ConfigTracker.defaultConfigName(SYNCED, "aeronautics")`, the
/// name the client's own `config/` directory carries.
const String aeroSyncedConfigFile = 'aeronautics-synced.toml';

/// Renders [server] as the body of [aeroSyncedConfigFile].
String aeroSyncedToml(AeroServerConfig server) {
  final toml = SyncedToml();

  final physics = server.physics;
  toml.table('physics');
  toml.value('recoil_magnitude', physics.mountedPotatoCannonMagnitude);
  toml.value('propellerBearingThrust', physics.propellerBearingThrust);
  // The Java key is `propellerBearingAirflow`; the port's field name carries the
  // Java field name (`propellerBearingAirflowMult`), not the config key.
  toml.value('propellerBearingAirflow', physics.propellerBearingAirflowMult);
  toml.value('woodenPropellerThrust', physics.woodenPropellerThrust);
  toml.value('woodenPropellerAirflow', physics.woodenPropellerAirflow);
  toml.value('andesitePropellerThrust', physics.andesitePropellerThrust);
  toml.value('andesitePropellerAirflow', physics.andesitePropellerAirflow);
  toml.value('smartPropellerThrust', physics.smartPropellerThrust);
  toml.value('smartPropellerAirflow', physics.smartPropellerAirflow);
  toml.value('hotAirStrength', physics.hotAirStrength);
  toml.value('steamStrength', physics.steamStrength);

  final blocks = server.blocks;
  toml.table('blocks');
  toml.value('break_blocks_on_levitite_crystallize', blocks.breakBlocksOnCrystallize);
  toml.value('hot_air_burner_max', blocks.hotAirBurnerMaxHotAir);
  toml.value('hot_air_burner_max_range', blocks.hotAirBurnerMaxRange);
  toml.value('steam_vent_hot_air_amount', blocks.steamVentMaxHotAir);
  toml.value('steam_vent_max_range', blocks.steamVentMaxRange);

  return toml.toString();
}
