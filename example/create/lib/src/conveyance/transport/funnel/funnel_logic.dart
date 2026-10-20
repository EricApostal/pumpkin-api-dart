// The funnel decisions that need no world (pure): whether the belt funnel above a depot or
// ejector may take that block's output (`DirectBeltInputBehaviour.tryExportingToBeltFunnel`) and
// how much a funnel extracts (`getAmountToExtract` / `getModeToExtract`).
import '../../../api/block_state.dart';
import '../../../common/direction.dart';
import '../../items/item_data.dart';
import '../block_predicates.dart';

/// `BeltFunnelBlock.Shape.PULLING`.
const String beltFunnelPulling = 'pulling';

/// The `null` cases of `DirectBeltInputBehaviour.tryExportingToBeltFunnel`: the block above has
/// to be a belt funnel in `PULLING` shape, and (when [side] is given) it has to face [side].
/// `null` means "this funnel does not take output at all"; a powered funnel still answers, it
/// just returns the stack unchanged.
bool beltFunnelTakesOutput(BState state, Direction? side) {
  if (!isBeltFunnelState(state)) return false;
  if (state['shape'] != beltFunnelPulling) return false;
  if (side != null && funnelFacing(state) != side) return false;
  return true;
}

/// `FunnelBlockEntity.getAmountToExtract`: an extractor without a filter takes one item at a
/// time, and a funnel that does not support amounts always takes a full stack.
int funnelExtractionAmount({
  required bool supportsAmount,
  required bool filterActive,
  required int filterAmount,
}) {
  if (!supportsAmount) return 64;
  return filterActive ? filterAmount : 1;
}

/// `FunnelBlockEntity.getModeToExtract`: `EXACTLY` only with an active filter on a funnel that
/// supports amounts.
ExtractionCountMode funnelExtractionMode({
  required bool supportsAmount,
  required bool filterActive,
  required bool filterUpTo,
}) {
  if (!supportsAmount || !filterActive) return ExtractionCountMode.upTo;
  return filterUpTo ? ExtractionCountMode.upTo : ExtractionCountMode.exactly;
}
