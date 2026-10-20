// Funnel state predicates (pure): the block keys and the `getFunnelFacing` rule of
// `AbstractFunnelBlock` / `BeltFunnelBlock`, kept free of the host bindings so the decisions built
// on them run on the plain Dart VM in tests.
import '../../api/block_state.dart';
import '../../common/direction.dart';

/// `AbstractFunnelBlock.isFunnel`.
bool isFunnelState(BState s) =>
    s.key == 'create:andesite_funnel' || s.key == 'create:brass_funnel';

/// `BeltFunnelBlock`.
bool isBeltFunnelState(BState s) =>
    s.key == 'create:andesite_belt_funnel' ||
    s.key == 'create:brass_belt_funnel';

/// `AbstractFunnelBlock.getFunnelFacing`.
Direction? funnelFacing(BState s) {
  if (isFunnelState(s)) return s.dir('facing');
  if (isBeltFunnelState(s)) return s.dir('facing');
  return null;
}
