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
import '../core/nbt.dart';
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

/// The keys `SmartBlockEntity.writeSafe` keeps through the safe behaviours of Create's block
/// entities. The port models the bracket behaviour (`BracketedBlockEntityBehaviour.isSafeNBT`);
/// the data of every other behaviour is dropped like Java drops an unsafe one.
const Set<String> safeBehaviourKeys = {'Bracket'};

/// `SmartBlockEntity.writeSafe` plus the [extraKeys] a block entity's own `writeSafe` adds on top
/// of the safe behaviour data (for example the connections of a chain conveyor).
List<int>? safeBlockEntityData(
  BState state,
  List<int>? nbt, {
  Iterable<String> extraKeys = const [],
}) {
  if (!state.key.startsWith('create:')) return null;
  if (nbt == null) return null;
  final parsed = BinaryNbt.read(nbt);
  if (parsed == null || parsed.root.kind != NbtKind.compound) return null;
  final root = parsed.root.asCompound;
  final kept = <String, NbtValue>{
    for (final key in [...safeBehaviourKeys, ...extraKeys])
      if (root[key] != null) key: root[key]!,
  };
  if (kept.isEmpty) return null;
  final id = root['id'];
  if (id != null) kept['id'] = id;
  return BinaryNbt.write(NbtValue.compound(kept), name: parsed.name);
}
