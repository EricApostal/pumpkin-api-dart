// `BlockStressValues` (pure): the API registries of stress impacts, stress capacities and
// generator RPM. The kinetics module reads its own stress table from the config; these registries
// are the extension point for blocks of other modules.

/// `BlockStressValues.GeneratedRpm`: the RPM a generator produces, for tooltips and the network.
final class GeneratedRpm {
  /// The generated speed at 1 RPM.
  final int value;

  /// `mayGenerateLess`: the generator may produce less (e.g. a water wheel).
  final bool mayGenerateLess;

  const GeneratedRpm(this.value, {this.mayGenerateLess = false});

  @override
  bool operator ==(Object other) =>
      other is GeneratedRpm &&
      other.value == value &&
      other.mayGenerateLess == mayGenerateLess;

  @override
  int get hashCode => Object.hash(value, mayGenerateLess);

  @override
  String toString() =>
      'GeneratedRpm($value${mayGenerateLess ? ', may generate less' : ''})';
}

/// `BlockStressValues`.
abstract final class BlockStressValues {
  /// `IMPACTS`: the base impact at 1 RPM, by block key.
  static final Map<String, double Function()> impacts = {};

  /// `CAPACITIES`: the base capacity at 1 RPM, by block key.
  static final Map<String, double Function()> capacities = {};

  /// `RPM`: the generated speed of a generator, by block key.
  static final Map<String, GeneratedRpm> rpm = {};

  /// `IMPACTS.register(block, supplier)`.
  static void registerImpact(String blockKey, double Function() supplier) =>
      impacts[blockKey] = supplier;

  /// `CAPACITIES.register(block, supplier)`.
  static void registerCapacity(String blockKey, double Function() supplier) =>
      capacities[blockKey] = supplier;

  /// `RPM.register(block, generatedRpm)`.
  static void registerRpm(String blockKey, GeneratedRpm generatedRpm) =>
      rpm[blockKey] = generatedRpm;

  /// `getImpact(block)`.
  static double getImpact(String blockKey) => impacts[blockKey]?.call() ?? 0;

  /// `getCapacity(block)`.
  static double getCapacity(String blockKey) =>
      capacities[blockKey]?.call() ?? 0;

  /// `setGeneratorSpeed(value)`: a registrar for [registerRpm].
  static void Function(String blockKey) setGeneratorSpeed(
    int value, {
    bool mayGenerateLess = false,
  }) =>
      (blockKey) => registerRpm(
        blockKey,
        GeneratedRpm(value, mayGenerateLess: mayGenerateLess),
      );

  /// Removes every registration (tests and reloads).
  static void clear() {
    impacts.clear();
    capacities.clear();
    rpm.clear();
  }
}
