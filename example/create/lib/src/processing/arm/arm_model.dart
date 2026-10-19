// The pure model of the mechanical arm: the interaction point modes, the arm's phases and the
// selection modes, plus the index arithmetic of `searchForItem` / `searchForDestination`.
//
// `content/kinetics/mechanicalArm/ArmInteractionPoint.java` (`Mode`),
// `ArmBlockEntity.java` (`Phase`, `SelectionMode`).
import '../../common/pos.dart';

/// `ArmInteractionPoint.Mode`.
enum ArmPointMode {
  /// Items go from the arm into the point.
  deposit,

  /// Items go from the point into the arm.
  take;

  /// The name Java writes to NBT (`Mode`).
  String get javaName => name.toUpperCase();

  static ArmPointMode fromJavaName(String? name) =>
      name == 'TAKE' ? ArmPointMode.take : ArmPointMode.deposit;

  ArmPointMode get cycled =>
      this == ArmPointMode.deposit ? ArmPointMode.take : ArmPointMode.deposit;
}

/// `ArmBlockEntity.Phase`.
enum ArmPhase {
  searchInputs,
  moveToInput,
  searchOutputs,
  moveToOutput,
  dancing;

  String get javaName => switch (this) {
    ArmPhase.searchInputs => 'SEARCH_INPUTS',
    ArmPhase.moveToInput => 'MOVE_TO_INPUT',
    ArmPhase.searchOutputs => 'SEARCH_OUTPUTS',
    ArmPhase.moveToOutput => 'MOVE_TO_OUTPUT',
    ArmPhase.dancing => 'DANCING',
  };

  static ArmPhase fromJavaName(String? name) {
    for (final p in ArmPhase.values) {
      if (p.javaName == name) return p;
    }
    return ArmPhase.searchInputs;
  }
}

/// `ArmBlockEntity.SelectionMode`.
enum ArmSelectionMode {
  roundRobin,
  forcedRoundRobin,
  preferFirst;

  static ArmSelectionMode fromOrdinal(int ordinal) =>
      values[ordinal.clamp(0, values.length - 1)];
}

/// The first index `searchForItem` / `searchForDestination` scans.
int armScanStart(ArmSelectionMode mode, int lastIndex) =>
    mode == ArmSelectionMode.preferFirst ? 0 : lastIndex + 1;

/// The exclusive end index of the scan.
int armScanRange(ArmSelectionMode mode, int lastIndex, int size) {
  final range = mode == ArmSelectionMode.forcedRoundRobin
      ? lastIndex + 2
      : size;
  return range > size ? size : range;
}

/// `ArmBlockEntity.getRange()`'s default (the config overrides it).
const int defaultArmRange = 5;

/// Whether [pos] is within [range] of [center] (`BlockPos.closerThan`).
bool armPointInRange(Pos center, Pos pos, int range) =>
    center.closerThan(pos, range.toDouble());
