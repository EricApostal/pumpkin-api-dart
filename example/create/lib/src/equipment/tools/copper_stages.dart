// The vanilla copper weathering / waxing data maps used by the sand paper
// (`DataMapHooks.getPreviousOxidizedStage`, `getBlockUnwaxed`). Pure; names follow vanilla.
abstract final class CopperStages {
  static const _mc = 'minecraft:';

  /// The previous oxidation stage of [blockKey] (`minecraft:weathered_cut_copper` ->
  /// `minecraft:exposed_cut_copper`), or `null` when it is not a weathered copper block.
  static String? previousOxidizedStage(String blockKey) {
    if (!blockKey.startsWith(_mc)) return null;
    final name = blockKey.substring(_mc.length);
    String? previous;
    if (name.startsWith('oxidized_')) {
      previous = 'weathered_${name.substring('oxidized_'.length)}';
    } else if (name.startsWith('weathered_')) {
      previous = 'exposed_${name.substring('weathered_'.length)}';
    } else if (name.startsWith('exposed_')) {
      final rest = name.substring('exposed_'.length);
      previous = rest == 'copper' ? 'copper_block' : rest;
    }
    return previous == null ? null : '$_mc$previous';
  }

  /// The block without wax (`minecraft:waxed_exposed_copper` -> `minecraft:exposed_copper`).
  static String? unwaxed(String blockKey) {
    if (!blockKey.startsWith(_mc)) return null;
    final name = blockKey.substring(_mc.length);
    if (!name.startsWith('waxed_')) return null;
    return '$_mc${name.substring('waxed_'.length)}';
  }
}
