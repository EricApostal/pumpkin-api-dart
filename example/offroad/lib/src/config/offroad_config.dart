// The server configuration of Offroad: the borehead bearing's search and stall
// parameters, and the stress impact of the mod's kinetic blocks.
//
// The Java mod registers these with Create's `ConfigBase`, which produces
// `offroad-server.toml` with the sections `[blocks]` and
// `[kinetics.stress.impact]` / `[kinetics.stress.capacity]`. A Pumpkin plugin
// reads one JSON document, so the sections keep the same names and the values
// keep the same keys, ranges and defaults: an existing server config keeps
// working after the keys are copied into `config.json`.
//
// Pure: no host imports.
//
// Java: `config/OffroadConfig.java`, `config/server/OffroadServer.java`,
//       `config/server/OffroadBlockConfigs.java`, `config/server/OffroadKinetics.java`,
//       `config/server/OffroadStress.java`
import '../index/offroad_ids.dart';

double _double(Map<String, Object?> map, String key, double fallback, double min, double max) {
  final value = map[key];
  if (value is num) return value.toDouble().clamp(min, max);
  return fallback;
}

int _int(Map<String, Object?> map, String key, int fallback, int min) {
  final value = map[key];
  if (value is num) return value.toInt().clamp(min, 1 << 31);
  return fallback;
}

bool _bool(Map<String, Object?> map, String key, bool fallback) {
  final value = map[key];
  return value is bool ? value : fallback;
}

Map<String, Object?> _section(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is Map<String, Object?> ? value : const {};
}

/// `OffroadBlockConfigs` (`config/server/OffroadBlockConfigs.java`).
final class OffroadBlockConfigs {
  /// `borehead_bearing_search_radius` (1.5, 0 to 10): the block gathering
  /// search radius of the borehead bearing (`OffroadBlockConfigs.java:7`).
  double boreheadBearingSearchRadius = 1.5;

  /// `borehead_bearing_stall_recovery_ticks` (10, at least 0): the ticks it
  /// takes for the bearing to recover from an item stall
  /// (`OffroadBlockConfigs.java:8`).
  int boreheadBearingStallRecoveryTicks = 10;

  /// `borehead_bearing_stalling_enabled` (true): whether the bearing stalls when
  /// it has no room for a mined block (`OffroadBlockConfigs.java:9`).
  bool boreheadBearingStallingEnabled = true;

  /// `borehead_bearing_rotation_divisor` (4, at least 1): divides the angular
  /// speed of the attached contraption (`OffroadBlockConfigs.java:11`).
  double boreheadBearingRotationDivisor = 4;

  OffroadBlockConfigs();

  /// Reads the `[blocks]` section; unknown keys are ignored.
  factory OffroadBlockConfigs.fromMap(Map<String, Object?> map) => OffroadBlockConfigs()
    ..boreheadBearingSearchRadius = _double(
      map,
      'borehead_bearing_search_radius',
      1.5,
      0,
      10,
    )
    ..boreheadBearingStallRecoveryTicks = _int(
      map,
      'borehead_bearing_stall_recovery_ticks',
      10,
      0,
    )
    ..boreheadBearingStallingEnabled = _bool(
      map,
      'borehead_bearing_stalling_enabled',
      true,
    )
    ..boreheadBearingRotationDivisor = _double(
      map,
      'borehead_bearing_rotation_divisor',
      4,
      1,
      double.infinity,
    );

  Map<String, Object?> toMap() => {
    'borehead_bearing_search_radius': boreheadBearingSearchRadius,
    'borehead_bearing_stall_recovery_ticks': boreheadBearingStallRecoveryTicks,
    'borehead_bearing_stalling_enabled': boreheadBearingStallingEnabled,
    'borehead_bearing_rotation_divisor': boreheadBearingRotationDivisor,
  };

  OffroadBlockConfigs copy() => OffroadBlockConfigs()
    ..boreheadBearingSearchRadius = boreheadBearingSearchRadius
    ..boreheadBearingStallRecoveryTicks = boreheadBearingStallRecoveryTicks
    ..boreheadBearingStallingEnabled = boreheadBearingStallingEnabled
    ..boreheadBearingRotationDivisor = boreheadBearingRotationDivisor;

  void restore(OffroadBlockConfigs other) {
    boreheadBearingSearchRadius = other.boreheadBearingSearchRadius;
    boreheadBearingStallRecoveryTicks = other.boreheadBearingStallRecoveryTicks;
    boreheadBearingStallingEnabled = other.boreheadBearingStallingEnabled;
    boreheadBearingRotationDivisor = other.boreheadBearingRotationDivisor;
  }
}

/// `OffroadStress` (`config/server/OffroadStress.java`).
///
/// The maps hold only the blocks Offroad called `setImpact` for, exactly like
/// the Java `DEFAULT_IMPACTS` / `DEFAULT_CAPACITIES` maps: Create's `CStress`
/// falls back to its own default for everything else, which is what
/// [defaultImpact] and [defaultCapacity] are.
final class OffroadStress {
  /// Create's default impact of a block that does not list one
  /// (`BlockStressValues.getImpact`).
  static const double defaultImpact = 1;

  /// Create's default capacity of a block that does not list one
  /// (`BlockStressValues.getCapacity`).
  static const double defaultCapacity = 0;

  /// `[kinetics.stress.impact]`, keyed by the config key (the id path).
  final Map<String, double> impacts = {
    // `OffroadBlocks.java:47`: `OffroadStress.setImpact(8)`.
    'borehead_bearing': 8,
    // `OffroadBlocks.java:97`: `OffroadStress.setImpact(16.0)`.
    'wheel_mount': 16,
  };

  /// `[kinetics.stress.capacity]`: nothing of Offroad generates stress, so the
  /// Java map stays empty (`OffroadStress.java:15-16`).
  final Map<String, double> capacities = {};

  OffroadStress();

  /// The impact of the block with id [key] (`offroad:borehead_bearing`).
  double impactOf(String key) => impacts[_pathOf(key)] ?? defaultImpact;

  /// The capacity of the block with id [key].
  double capacityOf(String key) => capacities[_pathOf(key)] ?? defaultCapacity;

  static String _pathOf(String key) => key.contains(':') ? key.split(':').last : key;

  factory OffroadStress.fromMap(Map<String, Object?> map) {
    final stress = OffroadStress();
    final impact = _section(map, 'impact');
    for (final entry in impact.entries) {
      final value = entry.value;
      if (value is num) stress.impacts[entry.key] = value.toDouble();
    }
    final capacity = _section(map, 'capacity');
    for (final entry in capacity.entries) {
      final value = entry.value;
      if (value is num) stress.capacities[entry.key] = value.toDouble();
    }
    return stress;
  }

  Map<String, Object?> toMap() => {
    'impact': Map<String, Object?>.of(impacts),
    'capacity': Map<String, Object?>.of(capacities),
  };

  OffroadStress copy() => OffroadStress()
    ..impacts.addAll(impacts)
    ..capacities.addAll(capacities);

  void restore(OffroadStress other) {
    impacts
      ..clear()
      ..addAll(other.impacts);
    capacities
      ..clear()
      ..addAll(other.capacities);
  }
}

/// `OffroadKinetics` (`config/server/OffroadKinetics.java`).
final class OffroadKinetics {
  /// The nested `stressValues` section.
  final OffroadStress stress = OffroadStress();

  OffroadKinetics();

  factory OffroadKinetics.fromMap(Map<String, Object?> map) => OffroadKinetics()
    ..stress.restore(OffroadStress.fromMap(_section(map, 'stress')));

  Map<String, Object?> toMap() => {'stress': stress.toMap()};

  OffroadKinetics copy() => OffroadKinetics()..stress.restore(stress);

  void restore(OffroadKinetics other) => stress.restore(other.stress);
}

/// `OffroadServer` (`config/server/OffroadServer.java`): the `server` file.
final class OffroadServerConfig {
  /// The `[blocks]` section.
  final OffroadBlockConfigs blocks = OffroadBlockConfigs();

  /// The `[kinetics]` section.
  final OffroadKinetics kinetics = OffroadKinetics();

  OffroadServerConfig();

  /// Reads the whole `config.json`; a missing section keeps its defaults.
  factory OffroadServerConfig.fromMap(Map<String, Object?> map) => OffroadServerConfig()
    ..blocks.restore(OffroadBlockConfigs.fromMap(_section(map, 'blocks')))
    ..kinetics.restore(OffroadKinetics.fromMap(_section(map, 'kinetics')));

  Map<String, Object?> toMap() => {
    'blocks': blocks.toMap(),
    'kinetics': kinetics.toMap(),
  };

  OffroadServerConfig copy() => OffroadServerConfig()
    ..blocks.restore(blocks)
    ..kinetics.restore(kinetics);

  void restore(OffroadServerConfig other) {
    blocks.restore(other.blocks);
    kinetics.restore(other.kinetics);
  }
}

/// `OffroadConfig` (`config/OffroadConfig.java`).
///
/// The Java interface also exposes a client config (`OffroadClientConfig`); the
/// values there are render-only and never read by a server, so the port has no
/// equivalent.
abstract final class OffroadConfig {
  /// The live server configuration. Every consumer reads it on use, so a config
  /// reload takes effect without rebuilding the objects that hold it.
  static OffroadServerConfig server = OffroadServerConfig();

  /// Restores the defaults (tests).
  static void reset() => server = OffroadServerConfig();

  /// `OffroadStress.setImpact(8)` of the borehead bearing (`OffroadBlocks.java:47`).
  static double get boreheadBearingImpact => server.kinetics.stress.impactOf(OffroadIds.boreheadBearing);

  /// `OffroadStress.setImpact(16)` of the wheel mount (`OffroadBlocks.java:97`).
  static double get wheelMountImpact => server.kinetics.stress.impactOf(OffroadIds.wheelMount);
}
