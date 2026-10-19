// `FenceGateMovingInteraction`: clicking a fence gate on a contraption toggles it.
//
// Java's `AllInteractionBehaviours` registers the *trapdoor* interaction for the fence gate tag;
// this class is ported for parity but is not the one the registry uses (see
// `all_movement_behaviours.dart`).
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/movement.dart';

final math.Random _random = math.Random();

/// `FenceGateMovingInteraction`.
final class FenceGateMovingInteraction extends SimpleBlockMovingInteraction {
  const FenceGateMovingInteraction();

  @override
  bool get updateColliders => true;

  @override
  BState handle(
    InteractingPlayer? player,
    Contraption contraption,
    Pos pos,
    BState currentState,
  ) {
    final sound = currentState.flag('open')
        ? 'minecraft:block.fence_gate.close'
        : 'minecraft:block.fence_gate.open';
    playSound(player, sound, _random.nextDouble() * 0.1 + 0.9);
    return currentState.cycleFlag('open');
  }
}
