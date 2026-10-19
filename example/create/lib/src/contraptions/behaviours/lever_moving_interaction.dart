// `LeverMovingInteraction`: clicking a lever on a contraption toggles it.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/movement.dart';

/// `LeverMovingInteraction`.
final class LeverMovingInteraction extends SimpleBlockMovingInteraction {
  const LeverMovingInteraction();

  @override
  BState handle(
    InteractingPlayer? player,
    Contraption contraption,
    Pos pos,
    BState currentState,
  ) {
    playSound(
      player,
      'minecraft:block.lever.click',
      currentState.flag('powered') ? 0.5 : 0.6,
    );
    return currentState.cycleFlag('powered');
  }
}
