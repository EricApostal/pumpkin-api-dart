// `SchematicPrinter` (pure): walks a [SchematicWorld] block by block and decides what the
// schematicannon (or the creative placement) has to do at each step.
import '../api/block_state.dart';
import '../common/binary_nbt.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'item_requirement.dart';
import 'material_checklist.dart';
import 'schematic_world.dart';

/// The real world as the printer needs to see it.
abstract interface class PrinterTargetView {
  bool isLoaded(Pos p);

  bool isWithinWorldBorder(Pos p);

  BState stateAt(Pos p);

  /// The block entity type key at [p], or null when there is none.
  String? blockEntityTypeAt(Pos p);

  /// `BlockState.hasBlockEntity()` for any block entity, vanilla or plugin.
  bool hasBlockEntity(BState state);

  /// `BlockState.getDestroySpeed(level, pos)`: -1 for unbreakable blocks.
  double destroySpeed(BState state);

  /// `BlockState.isRedstoneConductor(level, pos)`.
  bool isRedstoneConductor(BState state);

  /// Whether the fluid at [p] is water (`getFluidState(pos).is(Fluids.WATER)`).
  bool isWater(Pos p);
}

/// `SchematicPrinter.PrintStage`.
enum PrintStage { blocks, deferredBlocks, entities }

/// `PlacementPredicate`.
typedef PlacementPredicate = bool Function(
  Pos target,
  BState state,
  List<int>? blockEntity,
  BState toReplace,
  BState? toReplaceOther,
  bool isNormalCube,
);

/// `BlockTargetHandler`.
typedef BlockTargetHandler = void Function(
  Pos target,
  BState state,
  List<int>? blockEntityNbt,
);

/// `EntityTargetHandler`.
typedef EntityTargetHandler = void Function(Pos target, SchematicEntity entity);

/// `SchematicPrinter`.
final class SchematicPrinter {
  bool _schematicLoaded = false;
  bool _isErrored = false;
  SchematicWorld? _world;
  Pos? _anchor;

  /// Relative to the anchor.
  Pos? currentPos;
  int printingEntityIndex = -1;
  PrintStage printStage = PrintStage.blocks;
  final List<Pos> deferredBlocks = [];

  /// `BlockMovementChecks.isBrittle` and the blocks that must wait for their support.
  bool Function(BState state) isBrittle = (s) => false;

  /// The requirement lookup.
  SchematicRequirements requirements = SchematicRequirements();

  bool get isLoaded => _schematicLoaded;
  bool get isErrored => _isErrored;
  Pos? get anchor => _anchor;
  SchematicWorld? get world => _world;

  /// `isWorldEmpty`.
  bool get isWorldEmpty => _world?.isWorldEmpty ?? true;

  /// Loads [world] as the schematic to print (`loadSchematic` after the placement).
  void load(SchematicWorld world) {
    _world = world;
    _anchor = world.anchor;
    printingEntityIndex = -1;
    printStage = PrintStage.blocks;
    deferredBlocks.clear();
    final b = world.bounds;
    currentPos = (b.minX - 1, b.minY, b.minZ);
    _schematicLoaded = true;
    _isErrored = false;
  }

  /// A schematic that failed to load.
  void markErrored() {
    _schematicLoaded = true;
    _isErrored = true;
  }

  /// `resetSchematic`.
  void resetSchematic() {
    _schematicLoaded = false;
    _anchor = null;
    _isErrored = false;
    currentPos = null;
    _world = null;
    printingEntityIndex = -1;
    printStage = PrintStage.blocks;
    deferredBlocks.clear();
  }

  /// `getCurrentTarget`: the absolute position being worked on.
  Pos? get currentTarget {
    if (!isLoaded || isErrored) return null;
    return _anchor! + currentPos!;
  }

  // -- persistence ------------------------------------------------------------------------

  /// `fromTag` (server): the saved progress. [clientPacket] only reads the anchor.
  void fromTag(Map<String, Object?> tag, {bool clientPacket = false}) {
    final cp = tag['CurrentPos'];
    if (cp is List && cp.length == 3)
      currentPos = (cp[0] as int, cp[1] as int, cp[2] as int);
    if (clientPacket) {
      _schematicLoaded = false;
      final a = tag['Anchor'];
      if (a is List && a.length == 3) {
        _anchor = (a[0] as int, a[1] as int, a[2] as int);
        _schematicLoaded = true;
      }
    }
    printingEntityIndex = (tag['EntityProgress'] as int?) ?? 0;
    final stage = tag['PrintStage'] as String?;
    printStage = PrintStage.values.firstWhere(
      (s) =>
          s.name.toUpperCase() ==
          (stage ?? '').replaceAll('_', '').toUpperCase(),
      orElse: () => PrintStage.blocks,
    );
    deferredBlocks
      ..clear()
      ..addAll([
        for (final p in (tag['DeferredBlocks'] as List<Object?>? ?? const []))
          if (p is List && p.length == 3)
            (p[0] as int, p[1] as int, p[2] as int),
      ]);
  }

  /// `write`: the progress as plain data (position lists are `[x, y, z]`).
  Map<String, Object?> toTag() => {
    if (currentPos != null)
      'CurrentPos': [currentPos!.$1, currentPos!.$2, currentPos!.$3],
    if (_anchor != null) 'Anchor': [_anchor!.$1, _anchor!.$2, _anchor!.$3],
    'EntityProgress': printingEntityIndex,
    'PrintStage': switch (printStage) {
      PrintStage.blocks => 'BLOCKS',
      PrintStage.deferredBlocks => 'DEFERRED_BLOCKS',
      PrintStage.entities => 'ENTITIES',
    },
    'DeferredBlocks': [
      for (final p in deferredBlocks) [p.$1, p.$2, p.$3],
    ],
  };

  // -- walking -------------------------------------------------------------------------------

  /// `advanceCurrentPos`: moves to the next thing to print; false when everything was printed.
  bool advanceCurrentPos() {
    final entities = _world!.entities;
    do {
      if (printStage == PrintStage.blocks) {
        while (tryAdvanceCurrentPos()) {
          deferredBlocks.add(currentPos!);
        }
      }
      if (printStage == PrintStage.deferredBlocks) {
        if (deferredBlocks.isEmpty) {
          printStage = PrintStage.entities;
        } else {
          currentPos = deferredBlocks.removeAt(0);
        }
      }
      if (printStage == PrintStage.entities) {
        if (printingEntityIndex + 1 < entities.length) {
          printingEntityIndex++;
          currentPos = entities[printingEntityIndex].relativeBlockPos;
        } else {
          return false;
        }
      }
    } while (!_world!.bounds.isInside(currentPos!));
    return true;
  }

  /// `tryAdvanceCurrentPos`: one step along x, then z, then y; true while the block found must be
  /// deferred.
  bool tryAdvanceCurrentPos() {
    final bounds = _world!.bounds;
    var cp = currentPos!.relative(Direction.east);
    final inBounds = cp.offset(-bounds.minX, -bounds.minY, -bounds.minZ);
    // `BoundingBox.getXSpan()`/`getZSpan()`/`getYSpan()` are exclusive (`max - min`); the
    // inclusive spans of [BlockBounds] would step one column/layer too far.
    if (inBounds.$1 > bounds.maxX - bounds.minX)
      cp = (bounds.minX, cp.$2, cp.$3 + 1).west;
    if (inBounds.$3 > bounds.maxZ - bounds.minZ)
      cp = (cp.$1, cp.$2 + 1, bounds.minZ).west;
    currentPos = cp;
    // End of blocks reached
    if (cp.$2 > bounds.maxY) {
      printStage = PrintStage.deferredBlocks;
      return false;
    }
    return shouldDeferBlock(_world!.stateAt(cp));
  }

  /// `shouldDeferBlock`.
  bool shouldDeferBlock(BState state) =>
      state.key == 'create:gantry_carriage' ||
      state.key == 'create:mechanical_arm' ||
      isBrittle(state);

  /// `handleCurrentTarget`.
  void handleCurrentTarget(
    BlockTargetHandler blockHandler,
    EntityTargetHandler entityHandler,
  ) {
    final target = currentTarget!;
    if (printStage == PrintStage.entities) {
      entityHandler(target, _world!.entities[printingEntityIndex]);
    } else {
      final b = _world!.blockAt(currentPos!);
      blockHandler(target, setZeroAge(b.state), b.nbt);
    }
  }

  /// `BlockHelper.setZeroAge` on a state (growth properties reset).
  static BState setZeroAge(BState s) {
    for (final p in const ['age', 'level_honey', 'hatch', 'stage']) {
      if (s.has(p)) return s.setValue(p, '0');
    }
    if (_cauldrons.contains(s.key)) return const BState('minecraft:cauldron');
    if (s.key == 'minecraft:composter' && s.has('level')) {
      return s.setValue('level', '0');
    }
    if (s.has('extended')) return s.setFlag('extended', false);
    return s;
  }

  /// `BlockTags.CAULDRONS`.
  static const Set<String> _cauldrons = {
    'minecraft:cauldron',
    'minecraft:water_cauldron',
    'minecraft:lava_cauldron',
    'minecraft:powder_snow_cauldron',
  };

  // -- checks ----------------------------------------------------------------------------------

  /// `shouldPlaceCurrent(world)`.
  bool shouldPlaceCurrent(
    PrinterTargetView view, [
    PlacementPredicate? predicate,
  ]) {
    if (printStage == PrintStage.entities) return true;
    return shouldPlaceBlock(
      view,
      predicate ?? ((a, b, c, d, e, f) => true),
      currentTarget!,
    );
  }

  /// `shouldPlaceBlock` for the absolute [pos].
  bool shouldPlaceBlock(
    PrinterTargetView view,
    PlacementPredicate predicate,
    Pos pos,
  ) {
    final rel = pos - _anchor!;
    final schematicBlock = _world!.blockAt(rel);
    final state = setZeroAge(schematicBlock.state);
    final blockEntityNbt = schematicBlock.nbt;
    final toReplace = view.stateAt(pos);
    final toReplaceBeType = view.blockEntityTypeAt(pos);
    BState? toReplaceOther;
    if (state.has('part') &&
        state.has('facing') &&
        state['part'] == 'foot' &&
        _isBed(state.key)) {
      final d = Direction.byName(state['facing']!);
      if (d != null) toReplaceOther = view.stateAt(pos.relative(d));
    }
    if (state['half'] == 'lower') {
      toReplaceOther = view.stateAt(pos.above);
    }
    final newBe = blockEntityNbt == null
        ? null
        : requirements.blockEntityTypeOf(state.key);
    final mergeTEs =
        newBe != null && toReplaceBeType == newBe && _isMergeable(state.key);
    if (!view.isLoaded(pos)) return false;
    if (!view.isWithinWorldBorder(pos)) return false;
    if (toReplace == state && !mergeTEs) return false;
    if (view.destroySpeed(toReplace) == -1 ||
        (toReplaceOther != null && view.destroySpeed(toReplaceOther) == -1)) {
      return false;
    }
    final isNormalCube = view.isRedstoneConductor(state);
    return predicate(
      pos,
      state,
      blockEntityNbt,
      toReplace,
      toReplaceOther,
      isNormalCube,
    );
  }

  static bool _isBed(String key) => key.endsWith('_bed');

  /// Blocks implementing `IMergeableBE` (Create's blocks whose entities merge).
  bool _isMergeable(String key) => mergeableBlocks.contains(key);

  /// Block keys whose block entities merge instead of being replaced (`IMergeableBE`).
  /// `TrackBlockEntity` is the only implementation in Create.
  final Set<String> mergeableBlocks = {'create:track'};

  /// `getCurrentRequirement`.
  ItemRequirement getCurrentRequirement() {
    if (printStage == PrintStage.entities) {
      final e = _world!.entities[printingEntityIndex];
      final typeKey = SchematicPrinter.entityTypeOf(e);
      return typeKey == null
          ? ItemRequirement.invalid
          : requirements.ofEntity(typeKey, e.nbt);
    }
    final b = _world!.blockAt(currentPos!);
    return requirements.ofBlock(setZeroAge(b.state), b.nbt);
  }

  /// The entity type key of a schematic entity (its `id` tag).
  static String? entityTypeOf(SchematicEntity e) {
    final custom = entityTypeResolver;
    if (custom != null) return custom(e.nbt);
    return _idOfNbt(e.nbt);
  }

  /// Reads the `id` of entity NBT; a resolver can replace the binary parser.
  static String? Function(List<int> nbt)? entityTypeResolver;

  static String? _idOfNbt(List<int> nbt) {
    try {
      final parsed = BinaryNbt.read(nbt);
      if (parsed == null || parsed.root.kind != NbtKind.compound) return null;
      final id = parsed.root.asCompound['id'];
      return id != null && id.value is String ? id.value as String : null;
    } on Object {
      return null;
    }
  }

  /// `markAllBlockRequirements`: returns the number of blocks that have to be placed.
  int markAllBlockRequirements(
    MaterialChecklist checklist,
    PrinterTargetView view,
    PlacementPredicate predicate,
  ) {
    var blocksToPlace = 0;
    for (final rel in _world!.allPositions.toList()) {
      final pos = rel + _anchor!;
      final required = _world!.blockAt(rel);
      if (!view.isLoaded(pos)) {
        checklist.warnBlockNotLoaded();
        continue;
      }
      if (!shouldPlaceBlock(view, predicate, pos)) continue;
      final requirement = requirements.ofBlock(required.state, required.nbt);
      if (requirement.isEmpty) continue;
      if (requirement.isInvalid) continue;
      checklist.require(requirement);
      blocksToPlace++;
    }
    return blocksToPlace;
  }

  /// `markAllEntityRequirements`.
  void markAllEntityRequirements(MaterialChecklist checklist) {
    for (final e in _world!.entities) {
      final typeKey = entityTypeOf(e);
      final requirement = typeKey == null
          ? ItemRequirement.invalid
          : requirements.ofEntity(typeKey, e.nbt);
      // Java returns on the first entity without a requirement; continuing keeps the entities
      // after it on the checklist (a spawner-only entity should not hide the next one).
      if (requirement.isEmpty) continue;
      if (requirement.isInvalid) continue;
      checklist.require(requirement);
    }
  }

  /// `sendBlockUpdates`: the absolute positions around the schematic that hold water and need a
  /// fluid tick so the water flows into the printed area.
  List<Pos> waterPositionsToTick(PrinterTargetView view) {
    final b = _world!.bounds;
    final out = <Pos>[];
    for (final p in b.inflatedBy(1).positions()) {
      if (b.isInside(p)) continue;
      final abs = p + _anchor!;
      if (view.isLoaded(abs) && view.isWater(abs)) out.add(abs);
    }
    return out;
  }
}
