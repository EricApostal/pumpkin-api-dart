// The gases a balloon can be filled with, and the per-gas amounts.
//
// Java: `content/blocks/hot_air/lifting_gas/*`.
//
// Pure: no host imports.
import '../config/aero_config.dart';

/// `LiftingGasType`: one gas, with its fill and drain times and lift strength.
abstract interface class LiftingGasType {
  /// The translation key of the gas name (`aeronautics.lifting_gas.hot_air`).
  String get nameKey;

  /// Ticks to fill one cubic metre (9 seconds).
  double get fillingTime;

  /// Ticks to drain one cubic metre (9 seconds).
  double get emptyingTime;

  /// Kilopixel-grams of lift per cubic metre.
  double get liftStrength;

  /// How much the fill rate speeds up near the target.
  double get responsivenessAdjustmentFactor;

  /// The range of that speed-up, as a fraction of the balloon volume.
  double get responsivenessAdjustmentRange;
}

/// `DefaultLiftingGas`: hot air.
final class DefaultLiftingGas implements LiftingGasType {
  const DefaultLiftingGas();

  /// The registry id (`aeronautics:default`).
  static const String id = 'aeronautics:default';

  @override
  String get nameKey => 'aeronautics.lifting_gas.default';

  @override
  double get fillingTime => 9.0 * 20;

  @override
  double get emptyingTime => 9.0 * 20;

  @override
  double get liftStrength => AeroConfig.server.physics.hotAirStrength;

  @override
  double get responsivenessAdjustmentFactor => 5;

  @override
  double get responsivenessAdjustmentRange => 0.05;
}

/// `SteamLiftingGas`: the steam a steam vent makes.
final class SteamLiftingGas implements LiftingGasType {
  const SteamLiftingGas();

  /// The registry id (`aeronautics:steam`).
  static const String id = 'aeronautics:steam';

  @override
  String get nameKey => 'aeronautics.lifting_gas.steam';

  @override
  double get fillingTime => 9.0 * 20;

  @override
  double get emptyingTime => 9.0 * 20;

  @override
  double get liftStrength => AeroConfig.server.physics.steamStrength;

  @override
  double get responsivenessAdjustmentFactor => 5;

  @override
  double get responsivenessAdjustmentRange => 0.05;
}

/// `LiftingGasData`: the target, current amount and per-tick change of one gas.
final class LiftingGasData {
  double target;
  double amount;
  double nudge;

  LiftingGasData([this.target = 0, this.amount = 0, this.nudge = 0]);

  LiftingGasData copy() => LiftingGasData(target, amount, nudge);

  Map<String, Object?> toMap() => {'target': target, 'amount': amount, 'nudge': nudge};

  static LiftingGasData fromMap(Map<String, Object?> map) => LiftingGasData(
    (map['target'] as num?)?.toDouble() ?? 0,
    (map['amount'] as num?)?.toDouble() ?? 0,
    (map['nudge'] as num?)?.toDouble() ?? 0,
  );

  @override
  String toString() => 'LiftingGasData(target: $target, amount: $amount, nudge: $nudge)';
}

/// `LiftingGasHolder`: a gas and its data, as the balloon saves it.
final class LiftingGasHolder {
  final LiftingGasType type;
  final LiftingGasData data;

  const LiftingGasHolder(this.type, this.data);

  /// Two holders are equal when they hold the same gas (the Java record's
  /// `equals`).
  @override
  bool operator ==(Object other) => other is LiftingGasHolder && other.type == type;

  @override
  int get hashCode => type.hashCode;

  Map<String, Object?> toMap() => {'type': typeId(type), 'data': data.toMap()};

  static LiftingGasHolder fromMap(Map<String, Object?> map) =>
      LiftingGasHolder(gasById(map['type'] as String? ?? DefaultLiftingGas.id), LiftingGasData.fromMap(
        (map['data'] as Map?)?.cast<String, Object?>() ?? const {},
      ));

  /// The registry id of [type].
  static String typeId(LiftingGasType type) => switch (type) {
    DefaultLiftingGas() => DefaultLiftingGas.id,
    SteamLiftingGas() => SteamLiftingGas.id,
    _ => 'aeronautics:unknown',
  };

  /// The gas registered under [id]; an unknown id reads back as hot air.
  static LiftingGasType gasById(String id) => switch (id) {
    SteamLiftingGas.id => const SteamLiftingGas(),
    _ => const DefaultLiftingGas(),
  };
}
