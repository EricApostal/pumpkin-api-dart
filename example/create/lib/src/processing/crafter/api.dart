/// The public API of the crafter part of the processing module (re-exported by
/// `lib/src/api/processing.dart`).
///
/// * [MechanicalCrafterBlockEntity]: the crafter's slot, grid, connected input group and phase.
/// * [GroupedItems], [ConnectedInput], [CrafterPhase], [CrafterPointing]: the pure model of the
///   crafting grid and its chain.
/// * [crafterTargetDirection], [precedingCrafters], [allCraftersOfChainIf]: the chain traversal
///   over a [CrafterWorld].
/// * [mechanicalCraftingMatches], [craftingInputOf]: recipe matching for the grid.
library;

export 'crafter_block.dart' show CrafterKineticDef;
export 'crafter_model.dart';
export 'crafter_recipe.dart';
export 'mechanical_crafter_block_entity.dart' show MechanicalCrafterBlockEntity;
