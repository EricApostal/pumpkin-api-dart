// `AllSchematicStateFilters` (pure): states that are derived from block entity data and must not
// travel in a schematic.
import '../api/block_state.dart';

/// `SchematicStateFilterRegistry` for `minecraft:chiseled_bookshelf`: the occupied slots are
/// derived from the items in the block entity, so a placed bookshelf starts empty.
BState chiseledBookshelfFilter(List<int>? existingNbt, BState state) {
  var filtered = state;
  for (var slot = 0; slot < 6; slot++) {
    filtered = filtered.setFlag('slot_${slot}_occupied', false);
  }
  return filtered;
}
