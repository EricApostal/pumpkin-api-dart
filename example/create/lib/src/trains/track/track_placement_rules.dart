// The placement rules of the track blocks (pure: only the rule vocabulary of the host, so the
// parity harness can evaluate them on the plain Dart VM).
//
// Java -> Dart: `TrackBlock.getStateForPlacement` picks the track shape from the player's look and
// the neighbours along it; the host does the same from these rules when the item places the block
// (`crates/pumpkin-data/src/block_registry.rs`, `PlacementSource::TrackShape`).
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// The `placement:` rules of the `track` block: `TrackBlock.getStateForPlacement`, whose shape
/// follows the player's look (the nearest of the eight track axes), ascending when the neighbour
/// along it has a solid top and nothing solid above it. The host computes both from the placement
/// context, so no state write after the placement is needed.
const List<PlacementRule> trackPlacementRules = [
  PlacementRule.trackShape('shape'),
  PlacementRule.inWater('waterlogged'),
];
