// `simulated-synced.toml`: the mod's SYNCED server config, as the NeoForge
// handshake carries it to clients (`neoforge:config_file`).
//
// A NeoForge client with Simulated installed parses this body into the mod's
// `ModConfigSpec` and reads it *while building item tooltips*: Create's
// `KineticStats.getKineticStats` asks `BlockStressValues.getImpact(block)`,
// Simulated registered `SimStress::getImpact` as a provider, and the supplier it
// returns reads a `ConfigValue` of this file (`BlockStressValues.java:24-27`,
// `CStress.getImpact`). A client whose copy was never sent throws
// `IllegalStateException: Cannot get config value before config is loaded` on
// the first hover of a Simulated block, which is a client crash and not a
// tooltip difference: the Java server sends the file (`ConfigSync.syncAllConfigs`
// sends every SYNCED config of every installed mod) and the port has to as well.
//
// The paths are the Java ones (`SimServer`, `SimKinetics`, `SimStress`), not the
// plugin's JSON layout: the JSON section `server.kinetics.stress` is
// `kinetics.stressValues.v2` here, because `CStress.getName()` is
// `"stressValues.v" + VERSION`. A value the port does not model is left out and
// the client uses its own default, which is the Java default.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/infrastructure/config/synced_toml.dart';

import 'sim_config.dart';

/// The file name: `ConfigTracker.defaultConfigName(SYNCED, "simulated")`, the
/// name the client's own `config/` directory carries.
const String simSyncedConfigFile = 'simulated-synced.toml';

/// Renders [server] as the body of [simSyncedConfigFile].
///
/// The stress tables hold the values the plugin's `config.json` overrides
/// (`server.kinetics.stress.impact` / `.capacity`); Simulated's own defaults live
/// in the client's `ModConfigSpec`, so they need not be repeated here.
String simSyncedToml(SimServerConfig server) {
  final toml = SyncedToml();
  final kinetics = server.kinetics.stress;
  if (kinetics.configuredImpacts.isNotEmpty) {
    toml.table('kinetics.stressValues.v2.impact');
    for (final entry in kinetics.configuredImpacts.entries) {
      toml.value(entry.key, entry.value);
    }
  }
  if (kinetics.configuredCapacities.isNotEmpty) {
    toml.table('kinetics.stressValues.v2.capacity');
    for (final entry in kinetics.configuredCapacities.entries) {
      toml.value(entry.key, entry.value);
    }
  }

  final assembly = server.assembly;
  toml.table('assembly');
  toml.value('maxBlocksMoved', assembly.maxBlocksMoved);
  toml.value('honeyGlueRange', assembly.honeyGlueRange);
  toml.value('mergingGlueRange', assembly.mergingGlueRange);
  toml.value('maxDisassemblyTicks', assembly.maxDisassemblyTicks);
  toml.value('disassemblyDegreeTolerance', assembly.disassemblyDegreeTolerance);
  toml.value('disassemblyMaxVelocity', assembly.disassemblyMaxVelocity);
  toml.value('disassemblyMaxAngularVelocity', assembly.disassemblyMaxAngularVelocity);
  toml.value('disallowMidAirDisassembly', assembly.disallowMidAirDisassembly);
  // `SimAssembly.java:16` declares the key with a space in it.
  toml.value('Primary Disassembly', assembly.primaryDisassembly);

  final physics = server.physics;
  toml.table('physics');
  toml.value('redstoneMagnetStrength', physics.redstoneMagnetStrength);
  toml.value('dockingConnectorStrength', physics.dockingConnectorStrength);
  toml.value('redstoneMagnetLinearAccelerationClamping', physics.redstoneMagnetLinearAccelerationClamping);
  toml.value('redstoneMagnetAngularAccelerationClamping', physics.redstoneMagnetAngularAccelerationClamping);
  toml.value('dockingConnectorLinearAccelerationClamping', physics.dockingConnectorLinearAccelerationClamping);
  toml.value('dockingConnectorAngularAccelerationClamping', physics.dockingConnectorAngularAccelerationClamping);
  toml.value('swivel_stiffness', physics.swivelBearingStiffness);
  toml.value('swivel_friction', physics.swivelBearingFriction);
  toml.value('swivel_damping', physics.swivelBearingDamping);
  toml.value('docking_connector_angle', physics.dockingConnectorAngleTolerance);
  toml.value('docking_connector_distance', physics.dockingConnectorDistanceTolerance);
  toml.value('handleMaxForce', physics.handleMaxForce);
  toml.value('physics_staff_linear_stiffness', physics.physicsStaffLinearStiffness);
  toml.value('physics_staff_linear_damping', physics.physicsStaffLinearDamping);
  toml.value('physics_staff_angular_stiffness', physics.physicsStaffAngularStiffness);
  toml.value('physics_staff_angular_damping', physics.physicsStaffAngularDamping);

  final blocks = server.blocks;
  toml.table('blocks');
  toml.value('optical_sensor_max_range', blocks.opticalSensorRange);
  toml.value('laser_pointer_max_range', blocks.laserPointerRange);
  toml.value('max_rope_range', blocks.maxRopeRange);
  toml.value('max_rope_winch_stretch_allowed', blocks.maxRopeStretchAllowed);
  toml.value('max_rope_zipline_angle', blocks.maxRopeZiplineAngle);
  toml.value('max_swivel_bearing_speed', blocks.maxSwivelBearingSpeed);
  toml.value('docking_connector_fe_capacity', blocks.dockingConnectorFECapacity);
  toml.value('docking_connector_fe_throughput', blocks.dockingConnectorFEThroughput);

  final equipment = server.equipment;
  toml.table('equipment');
  toml.value('maxPlungerLauncherShots', equipment.maxPlungerLauncherShots);
  toml.value('maxPlungerLauncherRange', equipment.maxPlungerLauncherRange);

  return toml.toString();
}
