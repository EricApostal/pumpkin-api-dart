// Levitite blend crystallisation: the fluid a catalyzer turns into levitite.
//
// Java: `api/levitite_blend_crystallization/{CrystalPropagationContext,
// LevititeBlendHelper, LevititeBlendTicker, LevititeCrystallizerManager,
// CrystallizationWorldSaveData, LevititeBlendDummyInterface}` and
// `content/blocks/levitite/{LevititeCrystalPropagationContext,
// LevititeSoulCrystalPropagationContext}`, `util/CatalyzerHelper`.
//
// A blend source that sits next to a catalyzer (a lit blaze burner, or any block
// in a context's catalyzer tag) is queued as a *ticker*. The ticker waits out a
// dormant age, then each attempt rolls `attempts / maxAttempts`; a success
// replaces the blend with the context's crystal and queues the neighbouring
// blend, a failure re-arms the age. A ticker that requires a catalyzer is
// dropped as soon as no matching catalyzer is left.
//
// Pure: no host imports, so the whole state machine runs on the VM. The world it
// reads and writes is [LevititeWorld].
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

/// The world the crystallisation reads and writes.
abstract interface class LevititeWorld {
  /// The world id (`World.getId()`, the folder name `world`); keys the ticker lists. It is not a
  /// dimension key (`World.getDimension()`).
  String get id;

  /// The block key at [pos] (`minecraft:air` when empty).
  String blockKeyAt(Pos pos);

  /// The fluid key at [pos] (`minecraft:empty` when there is none).
  String fluidKeyAt(Pos pos);

  /// `level.setBlockAndUpdate`.
  void setBlock(Pos pos, String blockKey);

  /// `state.is(tag)` for the block at [pos].
  bool blockHasTag(Pos pos, String tag);

  /// The string value of block-state property [name] at [pos], or `null` when the
  /// block has no such property.
  String? blockPropertyAt(Pos pos, String name);

  /// `level.playSound(null, pos, sound, BLOCKS, volume, pitch)`.
  void playSound(String soundKey, Pos pos, {double volume = 1, double pitch = 1});

  /// `ServerLevel.sendParticles(type, x+0.5, y+0.5, z+0.5, count, 0.3, 0.3, 0.3, 0)`.
  void spawnParticles(String particle, Pos pos, int count);

  /// `advancement.awardToNearby(pos, level)`.
  void awardAdvancementNearby(String advancement, Pos pos);

  /// `BlockHelper.destroyBlock(level, pos, 1.0F)`.
  void destroyBlock(Pos pos);

  /// The saved data of the world was changed (`SavedData.setDirty`).
  void markDirty();

  /// `level.getRandom()`.
  math.Random get random;
}

/// The block key of the blend fluid (`aeronautics:levitite_blend`).
const String levititeBlendFluid = 'aeronautics:levitite_blend';

/// `LevititeCrystalPropagationContext`: what a blend crystallises into, and how.
abstract class CrystalPropagationContext {
  const CrystalPropagationContext();

  /// The registry id (`aeronautics:standard`).
  String get id;

  /// The tag that marks a block as a catalyzer for this context.
  String get catalyzerTag;

  /// The block this context crystallises into.
  String get crystalBlockKey;

  /// The advancement awarded next to a successful crystallisation.
  String get advancement;

  /// The particles of the initial burst, and of the crystal burst.
  String get flameParticle;
  String get initFlameParticle;

  /// `onCrystallizationInitialize`: the blend starts its dormant phase.
  void onCrystallizationInitialize(LevititeWorld world, Pos pos, bool isDormant) {
    world.playSound('minecraft:block.fire.extinguish', pos, volume: 0.2, pitch: 1.5);
    if (!isDormant) world.spawnParticles(initFlameParticle, pos, 20);
    world.spawnParticles('minecraft:smoke', pos, 15);
  }

  /// `onCrystallize`.
  void onCrystallize(LevititeWorld world, Pos pos) {
    onDefaultCrystallize(world, pos);
    world.playSound('aeronautics:levitite_blend_crystallize', pos);
    world.spawnParticles(flameParticle, pos, 30);
    world.awardAdvancementNearby(advancement, pos);
  }

  /// `onDefaultCrystallize`: place the crystal, then break the blocks the blend
  /// was touching that nothing else keeps wet.
  void onDefaultCrystallize(LevititeWorld world, Pos pos) {
    world.setBlock(pos, crystalBlockKey);
    if (!LevititeCrystallizationRules.breakBlocksOnCrystallize) return;

    for (final dir in Direction.values) {
      final neighbour = _offset(pos, dir);
      if (!world.blockHasTag(neighbour, 'aeronautics:levitite_breakable')) continue;

      var shouldBreak = true;
      for (final inner in Direction.values) {
        if (world.fluidKeyAt(_offset(neighbour, inner)) == levititeBlendFluid) {
          shouldBreak = false;
          break;
        }
      }
      if (shouldBreak) world.destroyBlock(neighbour);
    }
  }

  /// `onCrystallizationFail`.
  void onCrystallizationFail(LevititeWorld world, Pos pos, int attempts, bool isDormant) {
    world.spawnParticles('minecraft:smoke', pos, 15);
  }

  /// `getNewAge`: 10 to 39 ticks.
  int getNewAge(math.Random random) => 10 + random.nextInt(30);

  /// `shouldCrystallize`: `random < attempts / maxAttempts`.
  bool shouldCrystallize(math.Random random, int attempts, bool isDormant) {
    final maxAttempts = isDormant ? 10.0 : 5.0;
    return random.nextDouble() < attempts / maxAttempts;
  }

  /// `canSpreadTo`.
  bool canSpreadTo(String fluidKey) => fluidKey == levititeBlendFluid;

  /// `getContextForSpread`.
  CrystalPropagationContext getContextForSpread(LevititeWorld world, Pos pos);
}

/// The config the crystallisation reads (`AeroBlockConfigs`). Set by the module
/// so the pure code does not depend on the config singleton.
abstract final class LevititeCrystallizationRules {
  /// `break_blocks_on_levitite_crystallize`.
  static bool breakBlocksOnCrystallize = true;
}

/// `LevititeCrystalPropagationContext`: ordinary levitite.
final class StandardCrystalPropagationContext extends CrystalPropagationContext {
  const StandardCrystalPropagationContext();

  /// The registry id.
  static const String registryId = 'aeronautics:standard';

  @override
  String get id => registryId;

  @override
  String get catalyzerTag => 'aeronautics:levitite_catalyzer';

  @override
  String get crystalBlockKey => 'aeronautics:levitite';

  @override
  String get advancement => 'aeronautics:unidentified_floating_object';

  @override
  String get flameParticle => 'minecraft:flame';

  @override
  String get initFlameParticle => 'minecraft:flame';

  @override
  CrystalPropagationContext getContextForSpread(LevititeWorld world, Pos pos) =>
      randomContext(this, world, pos);
}

/// `LevititeSoulCrystalPropagationContext`: pearlescent levitite.
final class SoulCrystalPropagationContext extends CrystalPropagationContext {
  const SoulCrystalPropagationContext();

  /// The registry id.
  static const String registryId = 'aeronautics:soul';

  @override
  String get id => registryId;

  @override
  String get catalyzerTag => 'aeronautics:levitite_soul_catalyzer';

  @override
  String get crystalBlockKey => 'aeronautics:pearlescent_levitite';

  @override
  String get advancement => 'aeronautics:now_available_in_pink';

  @override
  String get flameParticle => 'minecraft:soul_fire_flame';

  @override
  String get initFlameParticle => 'minecraft:soul_fire_flame';

  @override
  CrystalPropagationContext getContextForSpread(LevititeWorld world, Pos pos) =>
      randomContext(this, world, pos);
}

/// The contexts in registration order (`AeroLevititeBlendPropagationContexts`).
const List<CrystalPropagationContext> levititeContexts = [
  StandardCrystalPropagationContext(),
  SoulCrystalPropagationContext(),
];

/// The context registered under [id], or `null`.
CrystalPropagationContext? levititeContextById(String id) {
  for (final context in levititeContexts) {
    if (context.id == id) return context;
  }
  return null;
}

/// `LevititeCrystalPropagationContext.getRandomContext`: the spread picks the
/// neighbouring catalyzer, weighted by how many of each sit next to it.
CrystalPropagationContext randomContext(
  CrystalPropagationContext self,
  LevititeWorld world,
  Pos pos,
) {
  final weights = _catalyzerWeights(world, pos);
  final sum = weights[0] + weights[1];
  if (sum == 0) return self;
  if (weights[0] > 0 && (weights[1] == 0 || world.random.nextInt(sum) < weights[0])) {
    return const StandardCrystalPropagationContext();
  }
  return const SoulCrystalPropagationContext();
}

/// `getWeights`: the adjacent standard and soul catalyzers.
List<int> _catalyzerWeights(LevititeWorld world, Pos pos) {
  final weights = [0, 0];
  for (final dir in Direction.values) {
    final at = _offset(pos, dir);
    if (world.blockHasTag(at, 'aeronautics:levitite_adjacent_catalyzer')) weights[0]++;
    if (world.blockHasTag(at, 'aeronautics:levitite_adjacent_soul_catalyzer')) weights[1]++;
  }
  return weights;
}

/// `LevititeBlendHelper.getContextFromBlock`: which context a block catalyzes,
/// or `null` when it catalyzes nothing.
///
/// A lit blaze burner is the standard catalyzer and a soul one the soul
/// catalyzer; any block with `lit = false` catalyzes nothing; otherwise the
/// contexts are tried in registration order against their catalyzer tags.
CrystalPropagationContext? contextFromBlock(LevititeWorld world, Pos pos) {
  final key = world.blockKeyAt(pos);
  if (key == 'create:blaze_burner') {
    final heat = world.blockPropertyAt(pos, 'blaze') ?? 'none';
    if (heat != 'none') return const StandardCrystalPropagationContext();
  }
  if (key == 'create:lit_blaze_burner') {
    final flame = world.blockPropertyAt(pos, 'flame_type') ?? 'regular';
    return flame == 'regular'
        ? const StandardCrystalPropagationContext()
        : const SoulCrystalPropagationContext();
  }

  final lit = world.blockPropertyAt(pos, 'lit');
  if (lit == 'false') return null;

  for (final context in levititeContexts) {
    if (world.blockHasTag(pos, context.catalyzerTag)) return context;
  }
  return null;
}

/// `CatalyzerHelper.isCatalyzer`: the item in hand may crystallise a blend.
///
/// [inTag] is the host's item-tag lookup (`Tags.item(key, tag)`); keeping it a
/// parameter is what lets the pure helper stay free of host imports.
bool isCatalyzer(String itemKey, {required bool Function(String key, String tag) inTag}) =>
    inTag(itemKey, 'aeronautics:levitite_catalyzer') ||
    inTag(itemKey, 'aeronautics:levitite_soul_catalyzer');

/// Whether the item is the soul variant of the catalyst (`is(AeroTags.ItemTags.
/// LEVITITE_SOUL_CATALYZER)`).
bool isSoulCatalyzer(String itemKey, {required bool Function(String key, String tag) inTag}) =>
    inTag(itemKey, 'aeronautics:levitite_soul_catalyzer');

/// `LevititeBlendTicker`: one blend position waiting to crystallise.
final class LevititeBlendTicker {
  /// The blend position.
  final Pos pos;

  /// The context the blend crystallises under.
  final CrystalPropagationContext context;

  /// Ticks left in the current phase.
  int age;

  /// Failed attempts so far, which raise the success chance.
  int attempts;

  /// Whether this ticker skipped the dormant phase.
  bool isDormant;

  /// Whether a matching catalyzer must stay next to the blend.
  final bool requiresCatalyst;

  LevititeBlendTicker(
    this.pos,
    this.context, {
    required this.age,
    this.attempts = 0,
    required this.isDormant,
    required this.requiresCatalyst,
  });

  /// The ticker a fresh blend starts as (`addTicker`).
  factory LevititeBlendTicker.fresh(
    Pos pos,
    CrystalPropagationContext context, {
    required bool requiresCatalyst,
    required bool isDormant,
    required math.Random random,
  }) => LevititeBlendTicker(
    pos,
    context,
    age: context.getNewAge(random),
    isDormant: isDormant,
    requiresCatalyst: requiresCatalyst,
  );

  /// `tick`: whether the ticker is done and must leave the list.
  bool tick(LevititeWorld world, math.Random random) {
    if (age > 0) {
      if (_checkSurroundingCatalyst(world)) return true;
      age--;
      return false;
    }

    if (world.fluidKeyAt(pos) != levititeBlendFluid) return true;

    if (context.shouldCrystallize(random, attempts, isDormant)) {
      crystallizeLevititeBlend(world, pos, context, random);
      return true;
    }

    context.onCrystallizationFail(world, pos, attempts, isDormant);
    age = context.getNewAge(random);
    attempts++;
    return false;
  }

  /// `checkSurroundingCatalyst`: a ticker that needs a catalyzer is dropped when
  /// none of the six neighbours gives the same context.
  bool _checkSurroundingCatalyst(LevititeWorld world) {
    if (!requiresCatalyst) return false;
    for (final dir in Direction.values) {
      final found = contextFromBlock(world, _offset(pos, dir));
      if (found == context) return false;
    }
    return true;
  }

  /// `serialize`: the tag the world saved data writes.
  Map<String, Object?> toMap() => {
    'age': age,
    'attempts': attempts,
    'requiresCatalyst': requiresCatalyst,
    'pos': [pos.$1, pos.$2, pos.$3],
    'context': context.id,
    'isDormant': isDormant,
  };

  /// `deserialize`: a ticker read back from the world saved data. An unknown
  /// context drops the ticker, as the Java constructor's `orElse(null)` did.
  static LevititeBlendTicker? fromMap(Map<String, Object?> map) {
    final context = levititeContextById(map['context'] as String? ?? '');
    if (context == null) return null;
    final rawPos = map['pos'];
    if (rawPos is! List || rawPos.length != 3) return null;
    return LevititeBlendTicker(
      ((rawPos[0] as num).toInt(), (rawPos[1] as num).toInt(), (rawPos[2] as num).toInt()),
      context,
      age: (map['age'] as num?)?.toInt() ?? 0,
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      isDormant: map['isDormant'] as bool? ?? false,
      requiresCatalyst: map['requiresCatalyst'] as bool? ?? false,
    );
  }
}

/// `LevititeBlendHelper.crystallizeLevititeBlend`.
void crystallizeLevititeBlend(
  LevititeWorld world,
  Pos pos,
  CrystalPropagationContext context,
  math.Random random,
) {
  context.onCrystallize(world, pos);
  updateSurroundingLevititeBlend(world, pos, context, random);
}

/// `LevititeBlendHelper.updateSurroundingLevititeBlend`: every neighbouring blend
/// that this context may spread into joins the queue.
void updateSurroundingLevititeBlend(
  LevititeWorld world,
  Pos pos,
  CrystalPropagationContext context,
  math.Random random,
) {
  for (final dir in Direction.values) {
    final neighbour = _offset(pos, dir);
    if (!context.canSpreadTo(world.fluidKeyAt(neighbour))) continue;
    LevititeCrystallizerManager.addTicker(
      world,
      neighbour,
      requiresCatalyst: false,
      isDormant: false,
      context: context.getContextForSpread(world, neighbour),
      random: random,
    );
  }
}

/// `LevititeBlendHelper.checkSurroundingSources`: a blend source next to a
/// catalyzer starts a ticker that must keep its catalyzer.
void checkSurroundingSources(LevititeWorld world, Pos pos, math.Random random) {
  if (world.fluidKeyAt(pos) != levititeBlendFluid) return;
  for (final dir in Direction.values) {
    final context = contextFromBlock(world, _offset(pos, dir));
    if (context == null) continue;
    LevititeCrystallizerManager.addTicker(
      world,
      pos,
      requiresCatalyst: true,
      isDormant: true,
      context: context,
      random: random,
    );
    return;
  }
}

/// `LevititeCrystallizerManager`: the ticker lists of every world.
abstract final class LevititeCrystallizerManager {
  /// The live tickers by world id.
  static final Map<String, List<LevititeBlendTicker>> _tickers = {};

  /// The tickers added since the last [tick], by world id.
  static final List<(String, LevititeBlendTicker)> _queued = [];

  /// The tickers of [worldId] (never null).
  static List<LevititeBlendTicker> tickersOf(String worldId) =>
      _tickers.putIfAbsent(worldId, () => []);

  /// The positions already ticked in [worldId].
  static Set<Pos> tickedPositions(String worldId) => {for (final t in tickersOf(worldId)) t.pos};

  /// `addTicker`: queues a ticker; it joins the list on the next [tick].
  static void addTicker(
    LevititeWorld world,
    Pos pos, {
    required bool requiresCatalyst,
    required bool isDormant,
    required CrystalPropagationContext context,
    required math.Random random,
  }) {
    if (tickedPositions(world.id).contains(pos)) return;
    _queued.add((
      world.id,
      LevititeBlendTicker.fresh(
        pos,
        context,
        requiresCatalyst: requiresCatalyst,
        isDormant: isDormant,
        random: random,
      ),
    ));
  }

  /// `tick`: advances the world's tickers and adopts the queued ones.
  static void tick(LevititeWorld world, math.Random random) {
    final list = tickersOf(world.id);
    list.removeWhere((ticker) => ticker.tick(world, random));

    final queued = [
      for (final entry in _queued)
        if (entry.$1 == world.id) entry.$2,
    ];
    if (queued.isEmpty) return;

    final ticked = tickedPositions(world.id);
    for (final ticker in queued) {
      if (ticked.contains(ticker.pos)) continue;
      list.add(ticker);
      ticked.add(ticker.pos);
      ticker.context.onCrystallizationInitialize(world, ticker.pos, ticker.isDormant);
      world.markDirty();
    }
    _queued.removeWhere((entry) => entry.$1 == world.id);
  }

  /// `saveData`: the tickers of [worldId] as the saved data's list.
  static List<Map<String, Object?>> saveData(String worldId) =>
      [for (final ticker in tickersOf(worldId)) ticker.toMap()];

  /// `loadData`: replaces the tickers of [worldId].
  static void loadData(String worldId, List<Object?> data) {
    final loaded = <LevititeBlendTicker>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final ticker = LevititeBlendTicker.fromMap(entry.cast<String, Object?>());
      if (ticker != null) loaded.add(ticker);
    }
    _tickers[worldId] = loaded;
  }

  /// `clearLevel`.
  static void clearLevel(String worldId) {
    _tickers.remove(worldId);
    _queued.removeWhere((entry) => entry.$1 == worldId);
  }

  /// Forgets everything (plugin unload, tests).
  static void clear() {
    _tickers.clear();
    _queued.clear();
  }
}

/// `BlockPos.relative`.
Pos _offset(Pos pos, Direction dir) => (pos.$1 + dir.stepX, pos.$2 + dir.stepY, pos.$3 + dir.stepZ);
