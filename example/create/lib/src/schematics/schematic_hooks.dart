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
/// entities, by the behaviour that writes them (each `writeSafe` defaults to `write`):
///
///   * `BracketedBlockEntityBehaviour` (`BracketedBlockEntityBehaviour.java:118-120`): `Bracket`
///   * `FilteringBehaviour` (`FilteringBehaviour.java:92-95`): `Filter`, `FilterAmount`, `UpTo`
///   * `ScrollValueBehaviour` (`ScrollValueBehaviour.java:64-65`, `ScrollOptionBehaviour` extends
///     it): `ScrollValue`
///   * `LinkBehaviour` (`LinkBehaviour.java:136-140`): `FrequencyFirst`, `FrequencyLast`,
///     `LastKnownPosition`
///   * `TrackTargetingBehaviour` (`TrackTargetingBehaviour.java:85-102`): `Id`, `TargetTrack`,
///     `Ortho`, `TargetDirection`, `RotatedAxis`, `PrevAxis`, `Migrate`, `Bezier`
///   * `LogisticallyLinkedBehaviour` (`LogisticallyLinkedBehaviour.java:236-238`, which overrides
///     `writeSafe` with `Freq` alone): `Freq`
///
/// The port models behaviours by their NBT keys, so a key is kept wherever it shows up instead of
/// only on the block entities that have that behaviour. Keys written by an unsafe behaviour of the
/// same name are excluded for their blocks ([unsafeBehaviourKeysOf]).
const Set<String> safeBehaviourKeys = {
  'Bracket',
  'Filter',
  'FilterAmount',
  'UpTo',
  'ScrollValue',
  'FrequencyFirst',
  'FrequencyLast',
  'LastKnownPosition',
  'Id',
  'TargetTrack',
  'Ortho',
  'TargetDirection',
  'RotatedAxis',
  'PrevAxis',
  'Migrate',
  'Bezier',
  'Freq',
};

/// The keys of [safeBehaviourKeys] an *unsafe* behaviour writes on the block entity [state], by
/// block key: `TableClothFilteringBehaviour.isSafeNBT` returns false
/// (`TableClothFilteringBehaviour.java:46-48`), so Java drops the price tag of a table cloth even
/// though it is a `FilteringBehaviour`.
Set<String> unsafeBehaviourKeysOf(BState state) =>
    state.key.endsWith('_table_cloth')
    ? const {'Filter', 'FilterAmount', 'UpTo'}
    : const {};

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
  final unsafe = unsafeBehaviourKeysOf(state);
  final kept = <String, NbtValue>{
    for (final key in [...safeBehaviourKeys, ...extraKeys])
      if (root[key] != null && !unsafe.contains(key)) key: root[key]!,
  };
  if (kept.isEmpty) return null;
  final id = root['id'];
  if (id != null) kept['id'] = id;
  return BinaryNbt.write(NbtValue.compound(kept), name: parsed.name);
}

/// The `PartialSafeNBT.writeSafe` writers of the Create block entities whose own data
/// `safeBlockEntityData` cannot tell apart from their unsafe data; they register into
/// [SchematicHooks.safeNbtWriters], keyed by block key. Call after the hooks exist
/// (`ctx.services.require<SchematicHooks>()`).
void registerCreateSafeNbtWriters(SchematicHooks hooks) {
  // `CopycatBlockEntity.writeSafe` (`CopycatBlockEntity.java:146-153`): the safe behaviour data
  // plus `Item` and `Material`. The block entity type covers the panel and the step
  // (`AllBlockEntityTypes.COPYCAT`), so both block keys get the writer;
  // `create:copycat_base` is only a material block state (`hasCustomMaterial`), not a copycat
  // block entity, and carries no data to keep.
  for (final key in const ['create:copycat_panel', 'create:copycat_step']) {
    hooks.safeNbtWriters[key] = _copycatSafeNbt;
  }
}

/// `CopycatBlockEntity.writeSafe`: `Item` (the item the material was copied from, saved without
/// its components) and `Material` (the imitated block state), next to the safe behaviours.
List<int>? _copycatSafeNbt(BState state, List<int>? nbt) {
  final data = safeBlockEntityData(
    state,
    nbt,
    extraKeys: const ['Item', 'Material'],
  );
  if (data == null) return null;
  final parsed = BinaryNbt.read(data);
  if (parsed == null || parsed.root.kind != NbtKind.compound) return data;
  final item = parsed.root.asCompound['Item'];
  if (item == null || item.kind != NbtKind.compound) return data;
  // `new ItemStack(consumedItem.typeHolder(), consumedItem.getCount(), DataComponentPatch.EMPTY)`.
  if (item.asCompound.remove('components') == null) return data;
  return BinaryNbt.write(parsed.root, name: parsed.name);
}
