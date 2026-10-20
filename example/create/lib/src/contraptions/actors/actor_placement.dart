// The placement rules of the attached actors (harvester, plough, roller) as pure data: which
// horizontal `facing` a placed actor gets. No host imports, so `dart test` reads them back and
// checks them against the Java rule.
//
// Java: `content/contraptions/actors/AttachedActorBlock.getStateForPlacement`.
import 'package:pumpkin_api/pumpkin_api_core.dart' show PlacementRule;

/// `AttachedActorBlock.getStateForPlacement`:
///
/// ```java
/// if (clickedFace.getAxis().isVertical())
///     facing = horizontalDirection.getOpposite();
/// else if (clickedState.getBlock() instanceof AttachedActorBlock)
///     facing = clickedState.getValue(FACING);
/// else
///     facing = clickedFace;
/// ```
///
/// The host has no source for "the clicked face when it is horizontal" and none for the clicked
/// block's `facing`, so the opposite of the look direction stands in: it is the clicked face
/// whenever the player clicks the face they look at, and it is the vertical-click branch as it is.
/// Only a click on a face the player does not look at, or on another actor, differs.
const List<PlacementRule> attachedActorPlacementRules = [
  PlacementRule.horizontalFacing('facing', opposite: true),
  PlacementRule.inWater('waterlogged'),
];
