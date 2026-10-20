// `dev.ryanhcode.sable.SableServerConfig` and
// `dev.ryanhcode.sable.physics.config.PhysicsConfigData`: the server-only
// settings, plus the solver settings they drive.
//
// The Java classes are NeoForge `ModConfigSpec` entries under
// `serverconfig/sable-server.toml`. The port has no loader config system, so
// these are plain fields with the same keys, defaults and ranges, read from the
// plugin's JSON config next to `SableConfig` (`config/sable_config.dart`).
//
// Pure: no host imports.
import '../config/sable_config.dart';

/// `SableServerConfig`: the two settings that are server-only.
final class SableServerConfig {
  /// `sub_level_substeps_per_tick`: how many physics substeps run per game
  /// tick. Range 1..10, default 2.
  int subLevelSubstepsPerTick;

  /// `sub_level_storage_pruning`: prune and delete empty sub-level storage
  /// files. Experimental; default off.
  bool subLevelStoragePruning;

  SableServerConfig({this.subLevelSubstepsPerTick = 2, this.subLevelStoragePruning = false});

  /// Reads the settings from a JSON object, keeping the defaults for missing
  /// keys and clamping the range the Java config declares.
  factory SableServerConfig.fromMap(Map<String, Object?> map) {
    final substeps = map['sub_level_substeps_per_tick'];
    final pruning = map['sub_level_storage_pruning'];
    return SableServerConfig(
      subLevelSubstepsPerTick: (substeps is num ? substeps.toInt() : 2).clamp(1, 10),
      subLevelStoragePruning: pruning is bool ? pruning : false,
    );
  }

  /// The settings as a JSON object.
  Map<String, Object?> toMap() => {
    'sub_level_substeps_per_tick': subLevelSubstepsPerTick,
    'sub_level_storage_pruning': subLevelStoragePruning,
  };
}

/// `PhysicsConfigData`: the solver settings handed to the physics pipeline.
///
/// `substepsPerTick` is the only value read from the config
/// (`updateFromConfig`); the rest are the Rapier defaults Sable tuned by hand
/// and that the Jolt pipeline maps onto its own solver.
final class PhysicsConfigData {
  /// Solver iterations for the constraint solver.
  int solverIterations = 18;

  /// PGS iterations.
  int pgsIterations = 2;

  /// Stabilization iterations.
  int stabilizationIterations = 2;

  /// Damping ratio of the contact spring.
  double contactSpringDampingRatio = 5.0;

  /// Natural frequency of the contact spring, in Hz.
  double contactSpringFrequency = 40.0;

  /// Minimum number of dynamic bodies in an active island.
  int minDynamicBodiesPerIsland = 128;

  /// Physics substeps per game tick.
  int substepsPerTick = 2;

  /// `updateFromConfig()`: reads `SableServerConfig.SUB_LEVEL_SUBSTEPS_PER_TICK`.
  void updateFromConfig(SableServerConfig config) {
    substepsPerTick = config.subLevelSubstepsPerTick;
  }

  /// The settings as a JSON object (diagnostics and tests).
  Map<String, Object?> toMap() => {
    'solver_iterations': solverIterations,
    'pgs_iterations': pgsIterations,
    'stabilization_iterations': stabilizationIterations,
    'contact_spring_damping_ratio': contactSpringDampingRatio,
    'contact_spring_frequency': contactSpringFrequency,
    'min_dynamic_bodies_per_island': minDynamicBodiesPerIsland,
    'substeps_per_tick': substepsPerTick,
  };
}

/// The config bundle the physics system reads: the shared Sable settings plus
/// the server-only ones.
final class SablePhysicsSettings {
  final SableConfig config;
  final SableServerConfig serverConfig;

  SablePhysicsSettings({required this.config, required this.serverConfig});
}
