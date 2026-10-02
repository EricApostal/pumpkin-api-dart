import 'package:wasm_components/wasm_components.dart' as wc;

import 'bindings.g.dart';

/// Conveniences for [AdvancementProgress].
extension AdvancementProgressExt on AdvancementProgress {
  /// Whether the advancement is fully completed.
  bool get isDone => done;

  /// Whether [criterion] has been awarded.
  bool isCriterionDone(String criterion) => awardedCriteria.contains(criterion);

  /// Completed fraction of criteria, from 0.0 to 1.0.
  double get fraction {
    final total = awardedCriteria.length + remainingCriteria.length;
    return total == 0 ? (done ? 1.0 : 0.0) : awardedCriteria.length / total;
  }
}

/// Advancement helpers on players.
extension PlayerAdvancements on Player {
  /// The progress of [advancementId] (like `minecraft:story/mine_stone`), or
  /// null if the advancement does not exist.
  AdvancementProgress? advancementProgress(String advancementId) {
    final wc.Option<AdvancementProgress> progress = getAdvancementProgress(
      advancementId: advancementId,
    );
    return progress.hasValue ? progress.requireValue() : null;
  }
}
