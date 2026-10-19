// The `kinetics` section of config.json: Create's `CKinetics` / `CStress`
// (server side) values that the kinetic network reads. Defaults come from the
// generated config manifest (`config_defaults.g.dart`).
import 'package:dart_mappable/dart_mappable.dart';

import '../manifest/stress.g.dart';
import 'geometry.dart';

part 'settings.mapper.dart';

/// The kinetic config values the network reads (`AllConfigs.server().kinetics`).
/// [KineticsSettings] is the stored fallback, `ConfigsKineticConfig` (in
/// `runtime.dart`) reads the live config of the infrastructure module.
abstract interface class KineticConfig {
  bool get disableStress;
  int get maxRotationSpeed;
  int get kineticValidationFrequency;
  double get mediumSpeed;
  double get fastSpeed;
  double get crankHungerMultiplier;
}

/// Impact / capacity per RPM of blocks (`BlockStressValues`).
abstract interface class StressSource {
  double impact(String block);
  double capacity(String block);
}

@MappableClass()
class KineticsSettings with KineticsSettingsMappable implements KineticConfig {
  /// `kinetics.disableStress`: disables the stress mechanic altogether.
  @override
  final bool disableStress;

  /// `kinetics.maxRotationSpeed` (RPM): faster blocks break.
  @override
  final int maxRotationSpeed;

  /// `kinetics.kineticValidationFrequency` (ticks): how often a block checks
  /// that its source is still valid.
  @override
  final int kineticValidationFrequency;

  /// `kinetics.stats.mediumSpeed` / `fastSpeed` (RPM): the speed level limits.
  @override
  final double mediumSpeed;
  @override
  final double fastSpeed;

  /// `kinetics.stats.*`: tooltip classes of stress impact and capacity.
  final double mediumStressImpact;
  final double highStressImpact;
  final double mediumCapacity;
  final double highCapacity;

  /// `kinetics.crankHungerMultiplier`: exhaustion per RPM of a turned crank.
  @override
  final double crankHungerMultiplier;

  /// `kinetics.stressValues.v2.impact.<key>` overrides (stress units per RPM),
  /// by block key without namespace. Keys that are not listed keep the default.
  final Map<String, double> stressImpacts;

  /// `kinetics.stressValues.v2.capacity.<key>` overrides.
  final Map<String, double> stressCapacities;

  const KineticsSettings({
    this.disableStress = false,
    this.maxRotationSpeed = maxRotationSpeedDefault,
    this.kineticValidationFrequency = 60,
    this.mediumSpeed = kineticsMediumSpeed,
    this.fastSpeed = kineticsFastSpeed,
    this.mediumStressImpact = kineticsMediumStressImpact,
    this.highStressImpact = kineticsHighStressImpact,
    this.mediumCapacity = kineticsMediumCapacity,
    this.highCapacity = kineticsHighCapacity,
    this.crankHungerMultiplier = 0.009999999776482582,
    this.stressImpacts = const {},
    this.stressCapacities = const {},
  });
}

/// `IRotate.SpeedLevel`.
enum SpeedLevel {
  none(0x000000, 0),
  slow(0x22FF22, 10),
  medium(0x0084FF, 20),
  fast(0xFF55FF, 30);

  /// The particle / dial colour.
  final int color;
  final int particleSpeed;

  const SpeedLevel(this.color, this.particleSpeed);

  /// `getSpeedValue()`: the minimum speed of the level.
  double speedValue(KineticConfig c) => switch (this) {
    SpeedLevel.fast => c.fastSpeed,
    SpeedLevel.medium => c.mediumSpeed,
    SpeedLevel.slow => 1,
    SpeedLevel.none => 0,
  };

  /// `SpeedLevel.of(speed)`.
  static SpeedLevel of(double speed, KineticConfig c) {
    speed = speed.abs();
    if (speed >= c.fastSpeed) return SpeedLevel.fast;
    if (speed >= c.mediumSpeed) return SpeedLevel.medium;
    if (speed >= 1) return SpeedLevel.slow;
    return SpeedLevel.none;
  }
}

/// `IRotate.StressImpact`.
enum StressImpactLevel {
  low,
  medium,
  high,
  overstressed;

  static StressImpactLevel of(double stressPercent) {
    if (stressPercent > 1) return StressImpactLevel.overstressed;
    if (stressPercent > .75) return StressImpactLevel.high;
    if (stressPercent > .5) return StressImpactLevel.medium;
    return StressImpactLevel.low;
  }
}

/// The stress impact / capacity per RPM of every block and the generated RPM of
/// generators (tooltips). Defaults are the generated stress table, overridden by
/// the config; modules may [register] more. (Unlike `BlockStressValues` of the
/// infrastructure module this is a plain table without live config values.)
final class KineticStressTable implements StressSource {
  final Map<String, double> _impacts = {};
  final Map<String, double> _capacities = {};
  final Map<String, ({int value, bool mayGenerateLess})> _rpm = {};

  /// The table of the manifest with the overrides of [settings].
  KineticStressTable([KineticsSettings settings = const KineticsSettings()]) {
    for (final e in stressDefaults) {
      final impact = e.impact;
      final capacity = e.capacity;
      if (impact != null) _impacts[e.block] = impact;
      if (capacity != null) _capacities[e.block] = capacity;
      final rpm = e.generatedRpm;
      if (rpm != null) _rpm[e.block] = (value: rpm, mayGenerateLess: e.mayGenerateLess ?? false);
    }
    _impacts.addAll(settings.stressImpacts);
    _capacities.addAll(settings.stressCapacities);
  }

  static String _path(String block) {
    final i = block.indexOf(':');
    return i < 0 ? block : block.substring(i + 1);
  }

  /// The stress impact per RPM of [block] (`create:shaft` or `shaft`), 0 if none.
  @override
  double impact(String block) => _impacts[_path(block)] ?? 0;

  /// The stress capacity per RPM of [block], 0 if none.
  @override
  double capacity(String block) => _capacities[_path(block)] ?? 0;

  /// The RPM generators of [block] produce (tooltips), if known.
  ({int value, bool mayGenerateLess})? generatedRpm(String block) => _rpm[_path(block)];

  /// Registers or replaces values of a block of another module.
  void register(String block, {double? impact, double? capacity, int? generatedRpm, bool mayGenerateLess = false}) {
    final p = _path(block);
    if (impact != null) _impacts[p] = impact;
    if (capacity != null) _capacities[p] = capacity;
    if (generatedRpm != null) _rpm[p] = (value: generatedRpm, mayGenerateLess: mayGenerateLess);
  }
}

/// `KineticBlockEntity.convertToDirection`.
double convertToDirection(double axisSpeed, Dir d) => d.isPositive ? axisSpeed : -axisSpeed;

/// `KineticBlockEntity.convertToLinear`: RPM to blocks per tick.
double convertToLinear(double speed) => speed / 512;

/// `KineticBlockEntity.convertToAngular`: RPM to degrees per tick.
double convertToAngular(double speed) => speed * 360 / 60 / 20;

/// `Color.mixColors(color1, color2, w)` as a signed 32 bit int (the NBT `Color`).
int mixColors(int color1, int color2, double w) {
  int channel(int shift) {
    final c1 = (color1 >> shift) & 0xFF;
    final c2 = (color2 >> shift) & 0xFF;
    return (c1 + (c2 - c1) * w).toInt();
  }

  final a1 = (color1 >> 24) & 0xFF;
  final a2 = (color2 >> 24) & 0xFF;
  final a = (a1 + (a2 - a1) * w).toInt();
  final result = (a << 24) + (channel(16) << 16) + (channel(8) << 8) + channel(0);
  return result.toSigned(32);
}

/// `Mth.lerp(t, a, b)`.
double lerp(double t, double a, double b) => a + t * (b - a);
