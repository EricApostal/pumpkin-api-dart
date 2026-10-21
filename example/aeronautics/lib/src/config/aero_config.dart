// The server configuration of Aeronautics: the physics scalars and the
// per-block limits. The values are the defaults of `AeroConfig` in the Java
// mod; a config file read at load replaces them through [AeroConfig.server].
//
// Pure: no host imports.
import 'dart:math' as math;

/// `AeroPhysics`: the thrust, airflow and lift scalars.
final class AeroPhysics {
  /// `propellerBearingThrust` (0.2).
  double propellerBearingThrust = 0.2;

  /// `propellerBearingAirflowMult` (0.05).
  double propellerBearingAirflowMult = 0.05;

  double woodenPropellerThrust = 1.0;
  double woodenPropellerAirflow = 0.1;
  double andesitePropellerThrust = 1.0;
  double andesitePropellerAirflow = 0.1;
  double smartPropellerThrust = 1.0;
  double smartPropellerAirflow = 0.1;

  /// `recoil_magnitude`: the recoil one mounted potato cannon shot applies
  /// (0.2).
  double mountedPotatoCannonMagnitude = 0.2;

  /// Kilopixel-grams lifted per cubic metre of hot air (1.5).
  double hotAirStrength = 1.5;

  /// Kilopixel-grams lifted per cubic metre of steam (1.5).
  double steamStrength = 1.5;

  /// A copy, for tests that change a value and restore it.
  AeroPhysics copy() => AeroPhysics()
    ..propellerBearingThrust = propellerBearingThrust
    ..propellerBearingAirflowMult = propellerBearingAirflowMult
    ..woodenPropellerThrust = woodenPropellerThrust
    ..woodenPropellerAirflow = woodenPropellerAirflow
    ..andesitePropellerThrust = andesitePropellerThrust
    ..andesitePropellerAirflow = andesitePropellerAirflow
    ..smartPropellerThrust = smartPropellerThrust
    ..smartPropellerAirflow = smartPropellerAirflow
    ..mountedPotatoCannonMagnitude = mountedPotatoCannonMagnitude
    ..hotAirStrength = hotAirStrength
    ..steamStrength = steamStrength;

  void restore(AeroPhysics other) {
    propellerBearingThrust = other.propellerBearingThrust;
    propellerBearingAirflowMult = other.propellerBearingAirflowMult;
    woodenPropellerThrust = other.woodenPropellerThrust;
    woodenPropellerAirflow = other.woodenPropellerAirflow;
    andesitePropellerThrust = other.andesitePropellerThrust;
    andesitePropellerAirflow = other.andesitePropellerAirflow;
    smartPropellerThrust = other.smartPropellerThrust;
    smartPropellerAirflow = other.smartPropellerAirflow;
    mountedPotatoCannonMagnitude = other.mountedPotatoCannonMagnitude;
    hotAirStrength = other.hotAirStrength;
    steamStrength = other.steamStrength;
  }
}

/// `AeroBlockConfigs`: the limits of the gas-producing blocks.
final class AeroBlockConfigs {
  /// `break_blocks_on_levitite_crystallize`.
  bool breakBlocksOnCrystallize = true;

  /// `hot_air_burner_max`: the most hot air one burner may output.
  int hotAirBurnerMaxHotAir = 500;

  /// `hot_air_burner_max_range`: how far a burner searches for a balloon.
  int hotAirBurnerMaxRange = 80;

  /// `steam_vent_hot_air_amount`.
  int steamVentMaxHotAir = 5000;

  /// `steam_vent_max_range`.
  int steamVentMaxRange = 80;
}

/// `AeroConfig.server()`.
final class AeroServerConfig {
  final AeroPhysics physics = AeroPhysics();
  final AeroBlockConfigs blocks = AeroBlockConfigs();
}

/// The mod configuration.
abstract final class AeroConfig {
  /// The live server configuration. Every consumer reads it on use, so a config
  /// reload takes effect without rebuilding the objects that hold it.
  static AeroServerConfig server = AeroServerConfig();

  /// Restores the defaults (tests).
  static void reset() => server = AeroServerConfig();

  /// `Mth.lerp(delta, start, end)`.
  static double lerp(double delta, double start, double end) =>
      start + delta * (end - start);

  /// `Mth.clamp`.
  static double clamp(double value, double min, double max) =>
      math.min(math.max(value, min), max);
}
