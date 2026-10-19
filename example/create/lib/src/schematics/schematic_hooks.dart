// The schematic extension points of Create's API (`api/schematic/*`) for other modules:
//
//   * `SchematicStateFilterRegistry`: [stateFilters], called when a block is placed from a
//     schematic over an existing block entity
//   * `SchematicRequirementRegistries`: [requirements]
//   * `SafeNbtWriterRegistry` / `PartialSafeNBT`: [safeNbtWriters]
//   * `BlockMovementChecks.isBrittle`: [isBrittle]
//   * belts: [beltHooks]
//
// Provided as a service by the schematics module: `ctx.services.require<SchematicHooks>()`.
import '../api/block_state.dart';
import '../common/common.dart';
import 'item_requirement.dart';

/// `StateFilter.filterStates(be, state)`: [existingNbt] is the block entity data of the block being
/// replaced (null when there is none).
typedef SchematicStateFilter = BState Function(List<int>? existingNbt, BState state);

/// `SafeNbtWriter.writeSafe`: returns the block entity data (binary NBT with `id`) that is allowed
/// to travel in a schematic, from the full data [nbt].
typedef SafeNbtWriter = List<int>? Function(BState state, List<int>? nbt);

/// What the kinetics module provides to place whole belts (`BeltConnectorItem.createBelts` and
/// `BeltBlockEntity.setCasingType`).
abstract interface class SchematicBeltHooks {
  /// Creates the belt between [start] and [end] in the world of the cannon.
  Future<void> createBelts(String worldId, Pos start, Pos end);

  /// Sets the casing of the belt segment at [pos] (1 andesite, 2 brass).
  Future<void> setCasing(String worldId, Pos pos, int casing);
}

/// The registries.
final class SchematicHooks {
  final SchematicRequirements requirements = SchematicRequirements();
  final Map<String, SchematicStateFilter> stateFilters = {};

  /// By block key; blocks tagged `create:safe_nbt` keep all their data without a writer.
  final Map<String, SafeNbtWriter> safeNbtWriters = {};
  final Set<String> mergeableBlocks = {};
  bool Function(BState state) isBrittle = (s) => false;
  SchematicBeltHooks? beltHooks;

  /// The block entity type key of a block, for [requirements] and for placing block entity data.
  String? Function(String blockKey) blockEntityTypeOf = (k) => null;
}
