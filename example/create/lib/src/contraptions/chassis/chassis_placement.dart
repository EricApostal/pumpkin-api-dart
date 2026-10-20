// The placement rules of the chassis family and the sticker as pure data: which `axis` a placed
// chassis gets and which `facing` a sticker gets. No host imports, so `dart test` reads them back
// and checks them against the Java rule.
//
// Java: `content/contraptions/chassis/{LinearChassisBlock,RadialChassisBlock,StickerBlock}` and
// `content/kinetics/base/RotatedPillarKineticBlock.getStateForPlacement`.
import 'package:pumpkin_api/pumpkin_api_core.dart' show PlacementRule;

/// `LinearChassisBlock.getStateForPlacement` (shared by the secondary chassis):
///
/// ```java
/// if (player == null || !player.isShiftKeyDown()) {
///     if (isChassis(clickedState)) return axis = clickedState.getValue(AXIS);
///     return axis = context.getNearestLookingDirection().getAxis();
/// }
/// return super.getStateForPlacement(context);   // RotatedPillarKineticBlock
/// ```
///
/// `RotatedPillarKineticBlock` takes the look axis, except that a sneaking player next to a shaft
/// gets the clicked face's axis instead (the shaft's axis is not used as the value there).
///
/// The host has neither a source for the clicked block's `axis` nor one for the axis of the
/// nearest looking direction (`clickedAxis` is the clicked *face*'s axis, `horizontalAxis` drops
/// the vertical look). The clicked face's axis stands in: it is the look axis whenever the player
/// clicks the face they look at, and it is the clicked face's axis in the sneaking-next-to-a-shaft
/// case. Only a click on a face the player does not look at, or on another chassis, differs.
const List<PlacementRule> linearChassisPlacementRules = [
  PlacementRule.clickedAxis('axis'),
];

/// `RadialChassisBlock` does not override `getStateForPlacement`: it is
/// `RotatedPillarKineticBlock.getStateForPlacement` (a shaft's axis, else the look axis, with the
/// clicked face's axis only for a sneaking player next to a shaft).
///
/// Same host gap as [linearChassisPlacementRules], so the same stand-in.
const List<PlacementRule> radialChassisPlacementRules = [
  PlacementRule.clickedAxis('axis'),
];

/// `StickerBlock.getStateForPlacement`: `getNearestLookingDirection()`, or its opposite when the
/// player does not sneak. `POWERED` comes from the neighbours in the block's `onPlaced`.
const List<PlacementRule> stickerPlacementRules = [
  PlacementRule.lookingDirection('facing', whenSneaking: true),
  PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
];
