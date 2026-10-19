// `BellMovementBehaviour`: bells on a contraption ring when the contraption starts moving, changes
// speed, or stops.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../core/movement.dart';
import '../actors/actor_runtime.dart';

/// `BellMovementBehaviour`.
final class BellMovementBehaviour extends MovementBehaviour {
  const BellMovementBehaviour();

  @override
  Future<void> tick(MovementContext context) async {
    final moved = context.temporaryData == true;
    if (moved) {
      playSound(context);
      context.temporaryData = null;
    }
  }

  @override
  void onSpeedChanged(MovementContext context, Vec3 oldMotion, Vec3 motion) {
    final dot = oldMotion.dot(motion);
    if (dot <= 0 && context.relativeMotion.length != 0 || context.firstMovement)
      playSound(context);
  }

  @override
  void stopMoving(MovementContext context) {
    if (context.position != null && isActive(context)) playSound(context);
  }

  /// `playSound`: the desk bell and Create's `AbstractBellBlock`s have their own sounds; everything
  /// else plays the vanilla bell.
  static void playSound(MovementContext context) {
    final world = actors?.worldOf(context);
    final position = context.position;
    if (world == null || position == null) return;

    final (
      String sound,
      double volume,
      double pitch,
    ) = switch (context.state.key) {
      'create:desk_bell' => ('create:desk_bell', 1, 1),
      'create:peculiar_bell' => ('create:peculiar_bell_use', 2, 0.94),
      'create:haunted_bell' => ('create:haunted_bell_use', 4, 1),
      _ => ('minecraft:block.bell.use', 2, 1),
    };
    world.playCustomSound(
      soundName: sound,
      category: SoundCategory.blocks,
      pos: position,
      volume: volume,
      pitch: pitch,
    );
  }
}
