// What each block of the decoration module is, derived from the block manifest (pure): the
// ownership rule, the role, the placement rules and the drops of every block.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../manifest/manifest.dart';

/// What a block of the module is.
enum DecorationRole {
  /// A plain block without logic (palette stone, casings, glass, windows, waxed copper).
  plain,
  casing,
  stairs,
  slab,
  wall,
  pane,
  pillar,
  copperFull,
  bracket,
  girder,
  encasedGirder,
  copycatPanel,
  copycatStep,
  copycatBars,
  copycatBase,
  placard,
  whistle,
  whistleExtension,
  slidingDoor,
  trapdoor,
  ladder,
  scaffolding,
  cardboard,
}

String shortClass(String javaClass) => javaClass.substring(javaClass.lastIndexOf('.') + 1);

bool isCreateCopper(ManifestBlock m) => m.key.contains('copper_shingle') || m.key.contains('copper_tile');

/// Whether [m] is a weathering copper block, decided by its block class: `CopperBlockSet` makes
/// the weathering variants of its sets (`BlockVariant`, `SlabVariant`, `StairVariant`) instances of
/// `WeatheringCopperFullBlock`, `WeatheringCopperSlabBlock` and `CreateWeatheringCopperStairBlock`,
/// all of them `ChangeOverTimeBlock`s, while the waxed variants are plain blocks. The name says
/// nothing: `create:copper_bars` is an `IronBarsBlock`, `copper_ladder` a `MetalLadderBlock` and
/// so on.
bool isWeatheringCopper(ManifestBlock m) => m.javaClass.contains('Weathering');

/// Whether [m] belongs to the decoration module: the blocks of `content/decoration` (and the vanilla
/// block families its palettes are made of), the copper sets, the bars, and the copycat base.
bool ownsBlock(ManifestBlock m) {
  if (m.javaClass.contains('.content.decoration.')) return true;
  if (m.source.startsWith('palette:') ||
      m.source.startsWith('AllPaletteBlocks.') ||
      m.source.startsWith('AllPaletteStoneTypes.') ||
      m.source.startsWith('AllBlocks.COPPER_SHINGLES') ||
      m.source.startsWith('AllBlocks.COPPER_TILES')) {
    return true;
  }
  return const {
    'andesite_bars',
    'brass_bars',
    'copper_bars',
    'copycat_base',
    'copycat_bars',
  }.contains(m.key);
}

/// The role of an owned block.
DecorationRole roleOf(ManifestBlock m) {
  if (m.key == 'copycat_base') return DecorationRole.copycatBase;
  if (m.key == 'copycat_bars') return DecorationRole.copycatBars;
  return switch (shortClass(m.javaClass)) {
    'BracketBlock' => DecorationRole.bracket,
    'GirderBlock' => DecorationRole.girder,
    'GirderEncasedShaftBlock' => DecorationRole.encasedGirder,
    'CopycatPanelBlock' => DecorationRole.copycatPanel,
    'CopycatStepBlock' => DecorationRole.copycatStep,
    'PlacardBlock' => DecorationRole.placard,
    'WhistleBlock' => DecorationRole.whistle,
    'WhistleExtenderBlock' => DecorationRole.whistleExtension,
    'SlidingDoorBlock' => DecorationRole.slidingDoor,
    'TrainTrapdoorBlock' => DecorationRole.trapdoor,
    'MetalLadderBlock' => DecorationRole.ladder,
    'MetalScaffoldingBlock' => DecorationRole.scaffolding,
    'CardboardBlock' => DecorationRole.cardboard,
    'CasingBlock' => DecorationRole.casing,
    'ConnectedPillarBlock' => DecorationRole.pillar,
    'ConnectedGlassPaneBlock' || 'GlassPaneBlock' || 'IronBarsBlock' => DecorationRole.pane,
    'StairBlock' || 'WeatheringCopperStairBlock' => DecorationRole.stairs,
    'SlabBlock' || 'WeatheringCopperSlabBlock' => DecorationRole.slab,
    'WallBlock' => DecorationRole.wall,
    'WeatheringCopperFullBlock' => DecorationRole.copperFull,
    _ => DecorationRole.plain,
  };
}

/// Blocks whose drops come from the data pack's loot table instead of "the block item".
bool usesLootTable(ManifestBlock m, DecorationRole role) =>
    role == DecorationRole.slab ||
    role == DecorationRole.slidingDoor ||
    role == DecorationRole.encasedGirder ||
    m.key == 'bound_cardboard_block' ||
    // Glass, panes and windows drop themselves only with silk touch.
    const {'TransparentBlock', 'ConnectedGlassBlock', 'WindowBlock', 'GlassPaneBlock', 'ConnectedGlassPaneBlock'}
        .contains(shortClass(m.javaClass));


/// The placement rules (`getStateForPlacement` parts the host can do by itself) of a [role].
List<PlacementRule> placementRulesOf(DecorationRole role) {
  const water = PlacementRule.inWater('waterlogged');
  return switch (role) {
    DecorationRole.stairs => const [PlacementRule.horizontalFacing('facing'), PlacementRule.clickedHalf('half'), water],
    DecorationRole.slab => const [PlacementRule.clickedHalf('type'), water],
    DecorationRole.wall || DecorationRole.pane || DecorationRole.placard || DecorationRole.trapdoor || DecorationRole.scaffolding => const [water],
    DecorationRole.pillar => const [PlacementRule.clickedAxis('axis')],
    DecorationRole.girder => const [PlacementRule.clickedAxis('axis'), water],
    DecorationRole.copycatPanel => const [PlacementRule.lookingDirection('facing', opposite: true), water],
    DecorationRole.copycatStep => const [PlacementRule.horizontalFacing('facing'), PlacementRule.clickedHalf('half'), water],
    DecorationRole.slidingDoor => const [PlacementRule.horizontalFacing('facing')],
    DecorationRole.ladder => const [PlacementRule.horizontalFacing('facing', opposite: true), water],
    _ => const [],
  };
}
