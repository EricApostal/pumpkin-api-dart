// The small pure model of the deployer: its two modes and its four animation states, and the
// conversions Java writes to NBT.
//
// `content/kinetics/deployer/DeployerBlockEntity.java` (`Mode`, `State`).

/// `DeployerBlockEntity.Mode`.
enum DeployerMode {
  punch,
  use;

  /// The name Java writes to NBT (`Mode`).
  String get javaName => name.toUpperCase();

  static DeployerMode fromJavaName(String? name) => switch (name) {
    'PUNCH' => DeployerMode.punch,
    _ => DeployerMode.use,
  };
}

/// `DeployerBlockEntity.State`.
enum DeployerState {
  waiting,
  expanding,
  retracting,
  dumping;

  /// The name Java writes to NBT (`State`).
  String get javaName => name.toUpperCase();

  static DeployerState fromJavaName(String? name) {
    for (final s in DeployerState.values) {
      if (s.javaName == name) return s;
    }
    return DeployerState.waiting;
  }
}
