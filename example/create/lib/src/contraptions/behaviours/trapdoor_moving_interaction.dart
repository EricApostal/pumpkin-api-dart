// `TrapdoorMovingInteraction`: clicking a trapdoor on a contraption toggles it.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/movement.dart';

final math.Random _random = math.Random();

/// `TrapdoorMovingInteraction`.
final class TrapdoorMovingInteraction extends SimpleBlockMovingInteraction {
  const TrapdoorMovingInteraction();

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
        ? 'minecraft:block.wooden_trapdoor.close'
        : 'minecraft:block.wooden_trapdoor.open';
    playSound(player, sound, _random.nextDouble() * 0.1 + 0.9);
    return currentState.cycleFlag('open');
  }
}
