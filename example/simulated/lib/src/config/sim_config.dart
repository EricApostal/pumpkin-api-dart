// The server config of Simulated, as plain data.
//
// The Java mod splits this over `config/server/*` and registers the fields with
// Create's `ConfigBase`. A Pumpkin plugin reads one JSON document, so the
// sections are ordinary classes with defaults and a `fromMap` that ignores
// unknown keys. Names and defaults match the Java config so an existing server
// config keeps working.
//
// Pure: no host imports.
import 'dart:math' as math;

/// Reads an int from [map], clamped to `[min, max]`.
int _int(Map<String, Object?> map, String key, int fallback, int min, int max) {
  final value = map[key];
  if (value is int) return value.clamp(min, max);
  if (value is num) return value.toInt().clamp(min, max);
  return fallback;
}

/// Reads a double from [map], clamped to `[min, max]`.
double _double(Map<String, Object?> map, String key, double fallback, double min, double max) {
  final value = map[key];
  if (value is num) return value.toDouble().clamp(min, max);
  return fallback;
}

/// Reads a bool from [map].
bool _bool(Map<String, Object?> map, String key, bool fallback) {
  final value = map[key];
  return value is bool ? value : fallback;
}

/// The nested map at [key], or an empty one.
Map<String, Object?> _section(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is Map<String, Object?> ? value : const {};
}

/// `config/server/blocks/SimAssembly`.
final class SimAssemblyConfig {
  /// Maximum number of blocks a structure may contain.
  final int maxBlocksMoved;

  /// Maximum edge length of a honey glue volume, in blocks.
  final int honeyGlueRange;

  /// Maximum distance merging glue may bridge, in blocks.
  final double mergingGlueRange;

  /// Ticks the disassembly alignment may take before it fails.
  final int maxDisassemblyTicks;

  /// Maximum tilt, in degrees, at which a sub-level may be disassembled.
  final double disassemblyDegreeTolerance;

  /// Maximum linear velocity, in m/s, at which a sub-level may be disassembled.
  final double disassemblyMaxVelocity;

  /// Maximum angular velocity, in rad/s, at which a sub-level may be disassembled.
  final double disassemblyMaxAngularVelocity;

  /// Whether a sub-level must be near terrain to be disassembled.
  final bool disallowMidAirDisassembly;

  /// Whether only the assembler that assembled a sub-level may disassemble it.
  final bool primaryDisassembly;

  const SimAssemblyConfig({
    this.maxBlocksMoved = 128000,
    this.honeyGlueRange = 48,
    this.mergingGlueRange = 4,
    this.maxDisassemblyTicks = 20,
    this.disassemblyDegreeTolerance = 4,
    this.disassemblyMaxVelocity = 5,
    this.disassemblyMaxAngularVelocity = math.pi / 2,
    this.disallowMidAirDisassembly = true,
    this.primaryDisassembly = false,
  });

  factory SimAssemblyConfig.fromMap(Map<String, Object?> map) => SimAssemblyConfig(
    maxBlocksMoved: _int(map, 'maxBlocksMoved', 128000, 1, 0x7fffffff),
    honeyGlueRange: _int(map, 'honeyGlueRange', 48, 1, 0x7fffffff),
    mergingGlueRange: _double(map, 'mergingGlueRange', 4, 0, double.maxFinite),
    maxDisassemblyTicks: _int(map, 'maxDisassemblyTicks', 20, 5, 0x7fffffff),
    disassemblyDegreeTolerance: _double(map, 'disassemblyDegreeTolerance', 4, 0, double.maxFinite),
    disassemblyMaxVelocity: _double(map, 'disassemblyMaxVelocity', 5, 0, double.maxFinite),
    disassemblyMaxAngularVelocity: _double(map, 'disassemblyMaxAngularVelocity', math.pi / 2, 0, double.maxFinite),
    disallowMidAirDisassembly: _bool(map, 'disallowMidAirDisassembly', true),
    primaryDisassembly: _bool(map, 'primaryDisassembly', false),
  );

  /// The Java default instance.
  static const SimAssemblyConfig defaults = SimAssemblyConfig();
}

/// `config/server/blocks/SimBlockConfigs`.
final class SimBlockConfig {
  final int opticalSensorRange;
  final int laserPointerRange;
  final double maxRopeRange;
  final double maxRopeStretchAllowed;
  final double maxRopeZiplineAngle;
  final double maxSwivelBearingSpeed;
  final int dockingConnectorFECapacity;
  final int dockingConnectorFEThroughput;

  const SimBlockConfig({
    this.opticalSensorRange = 15,
    this.laserPointerRange = 100,
    this.maxRopeRange = 40,
    this.maxRopeStretchAllowed = 25,
    this.maxRopeZiplineAngle = 85,
    this.maxSwivelBearingSpeed = 96,
    this.dockingConnectorFECapacity = 10000,
    this.dockingConnectorFEThroughput = 10000,
  });

  factory SimBlockConfig.fromMap(Map<String, Object?> map) => SimBlockConfig(
    opticalSensorRange: _int(map, 'optical_sensor_max_range', 15, 0, 0x7fffffff),
    laserPointerRange: _int(map, 'laser_pointer_max_range', 100, 0, 0x7fffffff),
    maxRopeRange: _double(map, 'max_rope_range', 40, 0, 1000),
    maxRopeStretchAllowed: _double(map, 'max_rope_winch_stretch_allowed', 25, 0, 100),
    maxRopeZiplineAngle: _double(map, 'max_rope_zipline_angle', 85, 0, 90),
    maxSwivelBearingSpeed: _double(map, 'max_swivel_bearing_speed', 96, 0, 256),
    dockingConnectorFECapacity: _int(map, 'docking_connector_fe_capacity', 10000, 0, 0x7fffffff),
    dockingConnectorFEThroughput: _int(map, 'docking_connector_fe_throughput', 10000, 0, 0x7fffffff),
  );

  static const SimBlockConfig defaults = SimBlockConfig();
}

/// `config/server/physics/SimPhysics`.
final class SimPhysicsConfig {
  final double redstoneMagnetStrength;
  final double dockingConnectorStrength;
  final double redstoneMagnetLinearAccelerationClamping;
  final double redstoneMagnetAngularAccelerationClamping;
  final double dockingConnectorLinearAccelerationClamping;
  final double dockingConnectorAngularAccelerationClamping;
  final double swivelBearingStiffness;
  final double swivelBearingFriction;
  final double swivelBearingDamping;
  final double dockingConnectorAngleTolerance;
  final double dockingConnectorDistanceTolerance;
  final double handleMaxForce;
  final double physicsStaffLinearStiffness;
  final double physicsStaffLinearDamping;
  final double physicsStaffAngularStiffness;
  final double physicsStaffAngularDamping;

  const SimPhysicsConfig({
    this.redstoneMagnetStrength = 1000,
    this.dockingConnectorStrength = 1000,
    this.redstoneMagnetLinearAccelerationClamping = 500,
    this.redstoneMagnetAngularAccelerationClamping = 50,
    this.dockingConnectorLinearAccelerationClamping = 500,
    this.dockingConnectorAngularAccelerationClamping = 50,
    this.swivelBearingStiffness = 1600,
    this.swivelBearingFriction = 0.3,
    this.swivelBearingDamping = 40,
    this.dockingConnectorAngleTolerance = 20,
    this.dockingConnectorDistanceTolerance = 0.5,
    this.handleMaxForce = 120,
    this.physicsStaffLinearStiffness = 2650,
    this.physicsStaffLinearDamping = 125,
    this.physicsStaffAngularStiffness = 10000,
    this.physicsStaffAngularDamping = 850,
  });

  factory SimPhysicsConfig.fromMap(Map<String, Object?> map) => SimPhysicsConfig(
    redstoneMagnetStrength: _double(map, 'redstoneMagnetStrength', 1000, 0, double.maxFinite),
    dockingConnectorStrength: _double(map, 'dockingConnectorStrength', 1000, 0, double.maxFinite),
    redstoneMagnetLinearAccelerationClamping:
        _double(map, 'redstoneMagnetLinearAccelerationClamping', 500, 0, double.maxFinite),
    redstoneMagnetAngularAccelerationClamping:
        _double(map, 'redstoneMagnetAngularAccelerationClamping', 50, 0, double.maxFinite),
    dockingConnectorLinearAccelerationClamping:
        _double(map, 'dockingConnectorLinearAccelerationClamping', 500, 0, double.maxFinite),
    dockingConnectorAngularAccelerationClamping:
        _double(map, 'dockingConnectorAngularAccelerationClamping', 50, 0, double.maxFinite),
    swivelBearingStiffness: _double(map, 'swivel_stiffness', 1600, 0, double.maxFinite),
    swivelBearingFriction: _double(map, 'swivel_friction', 0.3, 0, double.maxFinite),
    swivelBearingDamping: _double(map, 'swivel_damping', 40, 0, double.maxFinite),
    dockingConnectorAngleTolerance: _double(map, 'docking_connector_angle', 20, 0, 365),
    dockingConnectorDistanceTolerance: _double(map, 'docking_connector_distance', 0.5, 0, 4),
    handleMaxForce: _double(map, 'handleMaxForce', 120, 0, double.maxFinite),
    physicsStaffLinearStiffness: _double(map, 'physics_staff_linear_stiffness', 2650, 0, double.maxFinite),
    physicsStaffLinearDamping: _double(map, 'physics_staff_linear_damping', 125, 0, double.maxFinite),
    physicsStaffAngularStiffness: _double(map, 'physics_staff_angular_stiffness', 10000, 0, double.maxFinite),
    physicsStaffAngularDamping: _double(map, 'physics_staff_angular_damping', 850, 0, double.maxFinite),
  );

  static const SimPhysicsConfig defaults = SimPhysicsConfig();
}

/// `config/server/items/SimEquipment`.
final class SimEquipmentConfig {
  final int maxPlungerLauncherShots;
  final int maxPlungerLauncherRange;

  const SimEquipmentConfig({
    this.maxPlungerLauncherShots = 100,
    this.maxPlungerLauncherRange = 64,
  });

  factory SimEquipmentConfig.fromMap(Map<String, Object?> map) => SimEquipmentConfig(
    maxPlungerLauncherShots: _int(map, 'maxPlungerLauncherShots', 100, 0, 0x7fffffff),
    maxPlungerLauncherRange: _int(map, 'maxPlungerLauncherRange', 64, 0, 0x7fffffff),
  );

  static const SimEquipmentConfig defaults = SimEquipmentConfig();
}

/// `config/server/blocks/SimStress`: the stress impact and capacity overrides of
/// Simulated's own blocks, by block path (without the namespace).
///
/// Create keeps the base table; this section only holds the entries Simulated
/// registers (`setImpact`, `setCapacity`, `setNoImpact`), so the values follow
/// the registration and can be overridden from the config.
final class SimStressConfig {
  /// Default impacts by block path, in stress units.
  final Map<String, double> impacts;

  /// Default capacities by block path, in stress units.
  final Map<String, double> capacities;

  /// The values from the config file, which win over [impacts]/[capacities].
  final Map<String, double> configuredImpacts;
  final Map<String, double> configuredCapacities;

  const SimStressConfig({
    this.impacts = const {},
    this.capacities = const {},
    this.configuredImpacts = const {},
    this.configuredCapacities = const {},
  });

  factory SimStressConfig.fromMap(Map<String, Object?> map, {Map<String, double> impacts = const {}, Map<String, double> capacities = const {}}) {
    Map<String, double> read(String key) {
      final section = _section(map, key);
      final out = <String, double>{};
      for (final entry in section.entries) {
        final value = entry.value;
        if (value is num) out[entry.key] = value.toDouble();
      }
      return out;
    }

    return SimStressConfig(
      impacts: impacts,
      capacities: capacities,
      configuredImpacts: read('impact'),
      configuredCapacities: read('capacity'),
    );
  }

  /// The impact of [path]: the configured value, else the registered default.
  double impactOf(String path) => configuredImpacts[path] ?? impacts[path] ?? 0;

  /// The capacity of [path]: the configured value, else the registered default.
  double capacityOf(String path) => configuredCapacities[path] ?? capacities[path] ?? 0;
}

/// `config/server/blocks/SimKinetics`.
final class SimKineticsConfig {
  final SimStressConfig stress;

  const SimKineticsConfig({this.stress = const SimStressConfig()});

  factory SimKineticsConfig.fromMap(Map<String, Object?> map, {Map<String, double> impacts = const {}, Map<String, double> capacities = const {}}) =>
      SimKineticsConfig(stress: SimStressConfig.fromMap(_section(map, 'stress'), impacts: impacts, capacities: capacities));

  static const SimKineticsConfig defaults = SimKineticsConfig();
}

/// `config/server/SimServer`.
final class SimServerConfig {
  final SimKineticsConfig kinetics;
  final SimAssemblyConfig assembly;
  final SimPhysicsConfig physics;
  final SimBlockConfig blocks;
  final SimEquipmentConfig equipment;

  const SimServerConfig({
    this.kinetics = const SimKineticsConfig(),
    this.assembly = const SimAssemblyConfig(),
    this.physics = const SimPhysicsConfig(),
    this.blocks = const SimBlockConfig(),
    this.equipment = const SimEquipmentConfig(),
  });

  factory SimServerConfig.fromMap(Map<String, Object?> map) => SimServerConfig(
    kinetics: SimKineticsConfig.fromMap(_section(map, 'kinetics')),
    assembly: SimAssemblyConfig.fromMap(_section(map, 'assembly')),
    physics: SimPhysicsConfig.fromMap(_section(map, 'physics')),
    blocks: SimBlockConfig.fromMap(_section(map, 'blocks')),
    equipment: SimEquipmentConfig.fromMap(_section(map, 'equipment')),
  );

  static const SimServerConfig defaults = SimServerConfig();
}

/// The config of Simulated.
final class SimConfig {
  final SimServerConfig server;

  const SimConfig({this.server = const SimServerConfig()});

  /// Parses the `server` section of the plugin config; a missing or malformed
  /// section keeps the defaults.
  factory SimConfig.fromMap(Map<String, Object?> map) =>
      SimConfig(server: SimServerConfig.fromMap(_section(map, 'server')));

  static const SimConfig defaults = SimConfig();
}
