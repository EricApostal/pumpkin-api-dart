// The placement rules of the belt funnels as pure data: which horizontal `facing` a placed belt
// funnel gets. No host imports, so `dart test` reads them back and checks them against the Java
// rule.
//
// Java: `content/logistics/funnel/BeltFunnelBlock.getStateForPlacement`.
import 'package:pumpkin_api/pumpkin_api_core.dart' show PlacementRule;

/// `BeltFunnelBlock.getStateForPlacement`:
///
/// ```java
/// Direction facing = ctx.getClickedFace().getAxis().isHorizontal()
///     ? ctx.getClickedFace()
///     : ctx.getHorizontalDirection();
/// ```
///
/// The host has no source for "the clicked face when it is horizontal", and `clickedFace` cannot
/// be declared on a four-value property. The opposite of the look direction stands in: it is the
/// clicked face whenever the player clicks the face they look at (the usual belt-side click) and
/// it is off by 180° only for a click on a top or bottom face.
const List<PlacementRule> beltFunnelPlacementRules = [
  PlacementRule.horizontalFacing('facing', opposite: true),
  PlacementRule.inWater('waterlogged'),
];
