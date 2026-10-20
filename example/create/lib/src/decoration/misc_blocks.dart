// Smaller decoration blocks (pure): metal ladders, metal scaffolding, placards, cardboard blocks
// and the copper weathering/waxing rules of `CopperBlockSet`.
import '../api/block_state.dart';
import '../api/placement.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../manifest/blocks.g.dart';
import 'roles.dart';

// -- Ladders ---------------------------------------------------------------------------------

/// `MetalLadderBlock.canSurvive`: the vanilla ladder rule or another Create ladder of the same facing above.
bool ladderCanSurvive(BlockGetter level, Pos pos, BState state) {
  final facing = state.dir('facing')!;
  if (level.isFaceSturdy(pos.relative(facing.opposite), facing)) return true;
  final other = level.stateAt(pos.above);
  return other.key == state.key && other.dir('facing') == facing;
}

/// `MetalLadderBlock.updateShape`: the ladder breaks when it cannot survive.
BState ladderUpdateShape(BlockGetter level, Pos pos, BState state) =>
    ladderCanSurvive(level, pos, state) ? state : BState.air;

/// `LadderBlock.getStateForPlacement`: the first of [nearestLooking] (horizontal ones) that gives a
/// ladder that survives, or `null`. [clickedState] is the block the ladder is placed against.
BState? ladderStateForPlacement({
  required BlockGetter level,
  required Pos pos,
  required BState defaultState,
  required List<Direction> nearestLooking,
  required bool inWater,
  required bool replacingClickedOnBlock,
  required Direction clickedFace,
}) {
  if (!replacingClickedOnBlock) {
    final against = level.stateAt(pos.relative(clickedFace.opposite));
    if (against.key == defaultState.key && against.dir('facing') == clickedFace) return null;
  }
  for (final d in nearestLooking) {
    if (d.axis.isHorizontal) {
      final state = defaultState.setValue('facing', d.opposite.serializedName);
      if (ladderCanSurvive(level, pos, state)) return state.setFlag('waterlogged', inWater);
    }
  }
  return null;
}

/// `MetalLadderBlock.PlacementHelper.getOffset`: stacks another ladder above or below.
PlacementOffset ladderPlacementOffset({
  required BlockGetter level,
  required BState state,
  required Pos pos,
  required double playerPitch,
  required int range,
}) {
  final dir = playerPitch < 0 ? Direction.up : Direction.down;
  var ladders = 0;
  var check = pos.relative(dir);
  while (level.stateAt(check).has('facing') && _isLadderState(level, check)) {
    ladders++;
    check = check.relative(dir);
  }
  if (ladders >= range) return PlacementOffset.fail;
  final newPos = pos.relative(dir, ladders + 1);
  if (!ladderCanSurvive(level, newPos, state)) return PlacementOffset.fail;
  if (level.canBeReplaced(newPos)) {
    return PlacementOffset.at(newPos, (b) => b.setValue('facing', state['facing']!));
  }
  return PlacementOffset.fail;
}

/// `state.getBlock() instanceof LadderBlock`.
bool _isLadderState(BlockGetter level, Pos p) {
  final s = level.stateAt(p);
  final path = s.key.substring(s.key.indexOf(':') + 1);
  return path == 'ladder' || path.endsWith('_ladder');
}

// -- Scaffolding -----------------------------------------------------------------------------

/// `ScaffoldingBlock.getDistance` (vanilla scaffolding only: Create's scaffolding is not
/// `Blocks.SCAFFOLDING`, so it neither counts as support nor contributes a distance).
int scaffoldingDistance(BlockGetter level, Pos pos) {
  final below = pos.below;
  final belowState = level.stateAt(below);
  var distance = 7;
  if (belowState.key == 'minecraft:scaffolding') {
    distance = belowState.intValue('distance');
  } else if (level.isFaceSturdy(below, Direction.up)) {
    return 0;
  }
  for (final d in Direction.planeHorizontal) {
    final s = level.stateAt(pos.relative(d));
    if (s.key == 'minecraft:scaffolding') {
      final v = s.intValue('distance') + 1;
      if (v < distance) distance = v;
      if (distance == 1) break;
    }
  }
  return distance;
}

/// `ScaffoldingBlock.isBottom`.
bool scaffoldingIsBottom(BlockGetter level, Pos pos, int distance, String selfKey) =>
    distance > 0 && level.stateAt(pos.below).key != selfKey;

/// `ScaffoldingBlock.getStateForPlacement`.
BState scaffoldingStateForPlacement(BlockGetter level, Pos pos, BState defaultState) {
  final distance = scaffoldingDistance(level, pos);
  return defaultState
      .setFlag('waterlogged', level.isWater(pos))
      .setInt('distance', distance)
      .setFlag('bottom', scaffoldingIsBottom(level, pos, distance, defaultState.key));
}

/// `MetalScaffoldingBlock.updateShape`: the `bottom` flag follows the block below.
BState scaffoldingUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) {
  if (direction != Direction.down) return state;
  final below = level.stateAt(pos.below);
  return state.setFlag('bottom', below.key != state.key && !level.isFaceSturdy(pos.below, Direction.up));
}

/// `MetalScaffoldingBlockItem.updatePlacementContext`: where a click on an existing scaffolding
/// of the same block places the next one, or `null`.
Pos? scaffoldingItemTarget({
  required BlockGetter level,
  required String blockKey,
  required Pos clickedPos,
  required Direction clickedFace,
  required Direction horizontalDirection,
  required bool secondaryUse,
  bool isInside = false,
  required int minY,
  required int maxY,
}) {
  if (level.stateAt(clickedPos).key != blockKey) return clickedPos;
  Direction direction;
  if (secondaryUse) {
    direction = isInside ? clickedFace.opposite : clickedFace;
  } else {
    direction = clickedFace == Direction.up ? horizontalDirection : Direction.up;
  }
  var i = 0;
  var p = clickedPos.relative(direction);
  while (i < 7) {
    if (p.$2 < minY || p.$2 > maxY) break;
    final s = level.stateAt(p);
    if (s.key != blockKey) {
      if (level.canBeReplaced(p)) return p;
      break;
    }
    p = p.relative(direction);
    if (direction.axis.isHorizontal) i++;
  }
  return null;
}

// -- Placards --------------------------------------------------------------------------------

/// `PlacardBlock.canAttachLenient`: any block with a collision shape is enough.
bool placardCanSurvive(BlockGetter level, Pos pos, BState state) {
  final connected = _connectedDirection(state);
  if (connected == null) return false;
  return !level.collisionShapeEmpty(pos.relative(connected.opposite));
}

Direction? _connectedDirection(BState s) => switch (s['face']) {
  'ceiling' => Direction.down,
  'floor' => Direction.up,
  'wall' => s.dir('facing'),
  _ => null,
};

/// `PlacardBlock.getStateForPlacement` (`FaceAttachedHorizontalDirectionalBlock` plus Create's
/// floor flip): the first of [nearestLooking] that gives a placard that can stay.
BState? placardStateForPlacement({
  required BlockGetter level,
  required Pos pos,
  required BState defaultState,
  required List<Direction> nearestLooking,
  required Direction horizontalDirection,
  required bool inWater,
}) {
  for (final d in nearestLooking) {
    BState state;
    if (d.axis == Axis.y) {
      state = defaultState
          .setValue('face', d == Direction.up ? 'ceiling' : 'floor')
          .setValue('facing', horizontalDirection.serializedName);
    } else {
      state = defaultState.setValue('face', 'wall').setValue('facing', d.opposite.serializedName);
    }
    if (placardCanSurvive(level, pos, state)) {
      if (state['face'] == 'floor') {
        state = state.setValue('facing', state.dir('facing')!.opposite.serializedName);
      }
      return state.setFlag('waterlogged', inWater);
    }
  }
  return null;
}

/// `PlacardBlock.getSignal`: 15 on all sides while powered.
int placardSignal(BState state) => state.flag('powered') ? 15 : 0;

/// `PlacardBlock.getDirectSignal`: only toward the block it hangs on.
int placardDirectSignal(BState state, Direction side) =>
    state.flag('powered') && _connectedDirection(state) == side ? 15 : 0;

/// `PlacardBlock.updateShape`: the placard falls off when its support goes.
BState placardUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) {
  final connected = _connectedDirection(state);
  if (connected != null && connected.opposite == direction && !placardCanSurvive(level, pos, state)) return BState.air;
  return state;
}

/// Ticks a placard stays powered after a matching item was shown (`pte.poweredTicks = 19`).
const int placardPoweredTicks = 19;

// -- Cardboard -------------------------------------------------------------------------------

/// `CardboardBlock.rotate`.
BState cardboardRotate(BState state, BlockRotation rot) {
  final axis = state.axisOf('axis') ?? Axis.x;
  final rotated = rot.rotate(Direction.fromAxisAndDirection(axis, AxisDirection.positive)).axis;
  return state.setValue('axis', rotated.serializedName);
}

/// `CardboardBlock.getFireSpreadSpeed` / `getFlammability`.
const int cardboardFireSpread = 100;
const int cardboardFlammability = 20;

// -- Copper ----------------------------------------------------------------------------------

const List<String> copperStages = ['', 'exposed_', 'weathered_', 'oxidized_'];

/// The base names of the vanilla copper families whose names are `WeatherState` prefix + base
/// (`cut_copper` -> `exposed_cut_copper`), in the order of `WeatheringCopper.NEXT_BY_BLOCK`
/// (`WeatheringCopper.java:26-42`). Each one is a `WeatheringCopperCollection` whose weathering
/// factory is a weathering copper class, which is what makes the block weather: `Blocks.java:5265`
/// (CUT_COPPER, `WeatheringCopperFullBlock`), `:5272` (CHISELED_COPPER), `:5279`
/// (`WeatheringCopperStairBlock`), `:5286` (`WeatheringCopperSlabBlock`), `:5293`
/// (`WeatheringCopperDoorBlock`), `:5304` (`WeatheringCopperTrapDoorBlock`), `:2521`
/// (`WeatheringCopperBarsBlock`), `:5316` (`WeatheringCopperGrateBlock`), `:5331`
/// (`WeatheringCopperBulbBlock`), `:4562` (`WeatheringLanternBlock`), `:5351`
/// (`WeatheringCopperChestBlock`), `:5362` (`WeatheringCopperGolemStatueBlock`), `:2533`
/// (`WeatheringCopperChainBlock`) and `:5374` (`WeatheringLightningRodBlock`).
const List<String> vanillaWeatheringCopperBases = [
  'cut_copper',
  'chiseled_copper',
  'cut_copper_slab',
  'cut_copper_stairs',
  'copper_door',
  'copper_trapdoor',
  'copper_bars',
  'copper_grate',
  'copper_bulb',
  'copper_lantern',
  'copper_chest',
  'copper_golem_statue',
  'copper_chain',
  'lightning_rod',
];

/// The `copper_block` family alone does not spell its states `prefix + base`: its unaffected state
/// is `copper_block` and the others are `exposed_copper`, `weathered_copper`, `oxidized_copper`
/// (`BlockItemIds.java:789-793`).
const List<String> vanillaCopperBlockFamily = [
  'copper_block',
  'exposed_copper',
  'weathered_copper',
  'oxidized_copper',
];

/// The weathering copper blocks by key -> `WeatherState` ordinal (`UNAFFECTED` 0, `EXPOSED` 1,
/// `WEATHERED` 2, `OXIDIZED` 3).
///
/// The block **class** decides whether a block weathers, never its name:
/// `ChangeOverTimeBlock.getNextState` counts a neighbour only when it is a `ChangeOverTimeBlock`
/// whose `getAge()` enum class matches its own (`net/minecraft/world/level/block/ChangeOverTimeBlock.java`
/// `:27-62`, `isSameAgeingType` at `:59`). Waxed copper is a plain block, so it is absent here, and
/// a name containing "copper" means nothing (see [isWeatheringCopper] for Create's blocks).
final Map<String, int> _weatheringCopperAges = _buildWeatheringCopperAges();

Map<String, int> _buildWeatheringCopperAges() {
  final ages = <String, int>{};
  for (var stage = 0; stage < copperStages.length; stage++) {
    ages['minecraft:${vanillaCopperBlockFamily[stage]}'] = stage;
    for (final base in vanillaWeatheringCopperBases) {
      ages['minecraft:${copperStages[stage]}$base'] = stage;
    }
  }
  // Create's `CopperBlockSet` sets: the manifest records the class of every block, and the
  // weathering variants of the sets are the ones whose class is a weathering copper class.
  for (final m in kBlocks) {
    if (isWeatheringCopper(m)) ages['create:${m.key}'] = _stageOf(m.key);
  }
  return ages;
}

/// `WeatheringCopper.WeatherState` ordinal of the weathering copper block [key], or `null` when the
/// block does not weather (waxed variants, `copper_ore`, `copper_bars` of Create, a copycat of
/// copper, ...). A key without a namespace is a vanilla block.
int? copperWeatherAge(String key) {
  final colon = key.indexOf(':');
  return _weatheringCopperAges[colon < 0 ? 'minecraft:$key' : key];
}

/// The Create copper sets (`CopperBlockSet`): name -> variant suffix handling.
const List<String> copperSetNames = ['copper_shingles', 'copper_tiles'];

/// The unaffected, unwaxed key of a Create copper block for [setName] and [variant]
/// (`block`, `slab`, `stairs`).
String createCopperKey(String setName, String variant, {int stage = 0, bool waxed = false}) {
  var name = setName;
  switch (variant) {
    case 'slab':
      name = '${_nonPlural(name)}_slab';
    case 'stairs':
      name = '${_nonPlural(name)}_stairs';
  }
  return '${waxed ? 'waxed_' : ''}${copperStages[stage]}$name';
}

String _nonPlural(String name) => name.endsWith('s') ? name.substring(0, name.length - 1) : name;

int _stageOf(String path) {
  for (var i = 1; i < copperStages.length; i++) {
    if (path.startsWith(copperStages[i])) return i;
  }
  return 0;
}

/// The next weathering stage of a Create copper block (`CopperRegistries.getWeatheringView`):
/// `copper_shingles` -> `exposed_copper_shingles`, ..., `null` for the last stage and waxed blocks.
String? createCopperNext(String path) {
  if (path.startsWith('waxed_')) return null;
  final stage = _stageOf(path);
  if (stage >= copperStages.length - 1) return null;
  return '${copperStages[stage + 1]}${path.substring(copperStages[stage].length)}';
}

/// The previous stage (`CopperRegistries` inverse), used by axes scraping.
String? createCopperPrevious(String path) {
  if (path.startsWith('waxed_')) return null;
  for (var i = 1; i < copperStages.length; i++) {
    if (path.startsWith(copperStages[i])) return path.substring(copperStages[i].length);
  }
  return null;
}

/// The waxed version (`CopperRegistries.getWaxableView`), or `null` if [path] is already waxed.
String? createCopperWaxed(String path) => path.startsWith('waxed_') ? null : 'waxed_$path';

/// The unwaxed version of a waxed block.
String? createCopperUnwaxed(String path) => path.startsWith('waxed_') ? path.substring('waxed_'.length) : null;

/// `ChangeOverTimeBlock.getNextState`: whether the block at [pos] weathers to the next stage, given
/// the ages of the copper blocks within Manhattan distance 4 (the block itself excluded) and a
/// uniform random [roll] in [0, 1). The `0.05688889` chance of `changeOverTime` is tested by
/// the caller before this scan.
bool copperShouldAdvance(BlockGetter level, Pos pos, int ownAge, double roll) {
  var sameAge = 0;
  var older = 0;
  for (var dx = -4; dx <= 4; dx++) {
    for (var dy = -(4 - dx.abs()); dy <= 4 - dx.abs(); dy++) {
      final rem = 4 - dx.abs() - dy.abs();
      for (var dz = -rem; dz <= rem; dz++) {
        if (dx == 0 && dy == 0 && dz == 0) continue;
        final p = pos.offset(dx, dy, dz);
        final age = copperWeatherAge(level.stateAt(p).key);
        if (age == null) continue;
        if (age < ownAge) return false;
        if (age > ownAge) {
          older++;
        } else {
          sameAge++;
        }
      }
    }
  }
  final chance = (older + 1) / (older + sameAge + 1);
  final actual = chance * chance * (ownAge == 0 ? 0.75 : 1.0);
  return roll < actual;
}

/// The chance of `ChangeOverTimeBlock.changeOverTime` to even look at the neighbours.
const double copperChangeChance = 0.05688889;

/// Which axes tool strips: items with an `_axe` key (the `minecraft:axes` tag).
bool isAxeItem(String itemKey) => itemKey.endsWith('_axe');
